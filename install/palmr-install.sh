#!/usr/bin/env bash

# Copyright (c) 2025 Community Scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kyantech/Palmr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing & configuring Garage"
GITEA_RELEASE=$(curl -s https://api.github.com/repos/deuxfleurs-org/garage/tags | jq -r '.[0].name')
curl -fsSL "https://garagehq.deuxfleurs.fr/_releases/${GITEA_RELEASE}/x86_64-unknown-linux-musl/garage" -o /usr/bin/garage
chmod +x /usr/bin/garage
GARAGE_RPC_SECRET="$(openssl rand -hex 32)"
GARAGE_ADMIN_TOKEN="$(openssl rand -base64 32)"
GARAGE_METRICS_TOKEN="$(openssl rand -base64 32)"
cat <<EOF >/etc/garage.toml
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "sqlite"

replication_factor = 1

rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "${GARAGE_RPC_SECRET}"

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:9379"
root_domain = ".s3.garage.localhost"

[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.garage.localhost"
index = "index.html"

[admin]
api_bind_addr = "[::]:3903"
admin_token = "${GARAGE_ADMIN_TOKEN}"
metrics_token = "${GARAGE_METRICS_TOKEN}"
EOF
cat <<EOF >/etc/systemd/system/garage.service
[Unit]
Description=Garage Data Store
After=network-online.target
Wants=network-online.target

[Service]
Environment='RUST_LOG=garage=info' 'RUST_BACKTRACE=1'
ExecStart=/usr/bin/garage server
StateDirectory=garage
DynamicUser=true
ProtectHome=true
NoNewPrivileges=true
LimitNOFILE=42000

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now garage.service
sleep 2

NODE_ID="$(garage status | awk '{print $1}' | tail -n1)"
$STD garage layout assign -z dc1 -c 1G "$NODE_ID" &&
  $STD garage layout apply --version 1
$STD garage bucket create palmr-bucket
garage key create palmr-key | sed -n '2,4p' >~/.garage-palmr-key
$STD garage bucket allow palmr-bucket --key palmr-key --read --write --owner
KEY_ID="$(head -n1 ~/.garage-palmr-key | awk '{print $3}')"
SECRET_KEY="$(tail -n1 ~/.garage-palmr-key | awk '{print $3}')"
msg_ok "Installed & configured Garage"

fetch_and_deploy_gh_release "Palmr" "kyantech/Palmr" "tarball" "latest" "/opt/palmr"
PNPM="$(jq -r '.packageManager' /opt/palmr/package.json)"
NODE_VERSION="24" NODE_MODULE="$PNPM" setup_nodejs

msg_info "Configuring palmr backend"
LOCAL_IP="$(hostname -I | awk '{print $1}')"
PALMR_DIR="/opt/palmr_data"
mkdir -p "$PALMR_DIR"
PALMR_DB="${PALMR_DIR}/palmr.db"
PALMR_KEY="$(openssl rand -hex 32)"
cd /opt/palmr/apps/server
sed -e '/ENABLE_S3/d' \
  -e 's/^# S3/S3/' \
  -e 's/_ENCRYPTION=true/_ENCRYPTION=false/' \
  -e "/^# ENC/s/# //; s/ENCRYPTION_KEY=.*$/ENCRYPTION_KEY=$PALMR_KEY/" \
  -e "s|file:.*$|file:$PALMR_DB\"|" \
  -e 's/S3_ENDPOINT=$/&127.0.0.1/' \
  -e 's/S3_PORT=$/&9379/' \
  -e "s|S3_ACCESS_KEY=$|&$KEY_ID|" \
  -e "s|S3_SECRET_KEY=$|&$SECRET_KEY|" \
  -e 's/S3_BUCKET_NAME=$/&palmr-storage/' \
  -e 's/S3_REGION=$/&garage/' \
  -e 's/S3_USE_SSL=$/&false/' \
  -e 's/S3_FORCE_PATH_STYLE=$/&false/' \
  -e 's/UNAUTHORIZED=true.*$/UNAUTHORIZED=true/' \
  -e "\|db\"$|a\\STORAGE_URL=\"http://${LOCAL_IP}:9379\"\\
# Uncomment below when using a reverse proxy\\
# SECURE_SITE=true\\
# Uncomment and add your path if using symlinks for data storage\\
# CUSTOM_PATH=<path-to-your-bind-mount>" \
  .env.example >./.env
$STD pnpm install
$STD npx prisma generate
$STD npx prisma migrate deploy
$STD npx prisma db push
$STD pnpm db:seed
$STD pnpm build
msg_ok "Configured palmr backend"

msg_info "Configuring palmr frontend"
cd /opt/palmr/apps/web
mv ./.env.example ./.env
export NODE_ENV=production
export NEXT_TELEMETRY_DISABLED=1
$STD pnpm install
$STD pnpm build
msg_ok "Configured palmr frontend"

msg_info "Creating service"
useradd -d "$PALMR_DIR" -M -s /usr/sbin/nologin -U palmr
chown -R palmr:palmr "$PALMR_DIR" /opt/palmr
cat <<EOF >/etc/systemd/system/palmr-backend.service
[Unit]
Description=palmr Backend Service
After=network.target

[Service]
Type=simple
User=palmr
Group=palmr
WorkingDirectory=/opt/palmr_data
ExecStart=/usr/bin/node /opt/palmr/apps/server/dist/server.js

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/palmr-frontend.service
[Unit]
Description=palmr Frontend Service
After=network.target palmr-backend.service

[Service]
Type=simple
User=palmr
Group=palmr
WorkingDirectory=/opt/palmr/apps/web
ExecStart=/usr/bin/pnpm start

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now palmr-backend palmr-frontend
msg_ok "Created service"

motd_ssh
customize
cleanup_lxc
