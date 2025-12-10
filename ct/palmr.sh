#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kyantech/Palmr

APP="Palmr"
var_tags="${var_tags:-files}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/palmr_data ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "palmr" "kyantech/Palmr"; then
    msg_info "Stopping Services"
    systemctl stop palmr-frontend palmr-backend
    msg_ok "Stopped Services"

    if [[ -d /var/lib/garage ]]; then
      msg_info "Installing & configuring Garage"
      download_file "https://garagehq.deuxfleurs.fr/_releases/v2.1.0/x86_64-unknown-linux-musl/garage" "/usr/bin" && chmod +x /usr/bin/garage
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
      NODE_ID="$(garage status | awk '{print $1}' | head -n1)"
      $STD garage layout assign -z dc1 -c 1G "$NODE_ID" &&
        $STD garage layout apply --version 1
      $STD garage bucket create palmr-bucket
      garage key create palmr-key | sed -n '2,4p' ~/.garage-palmr-key
      $STD garage bucket allow --read --write --owner palmr-bucket palmr-key
      KEY_ID="$(head -n1 ~/.garage-palmr-key | awk '{print $3}')"
      SECRET_KEY="$(tail -n1 ~/.garage-palmr-key | awk '{print $3}')"
      msg_ok "Installed & configured Garage"
    fi

    cp /opt/palmr/apps/server/.env /opt/palmr.env
    rm -rf /opt/palmr
    fetch_and_deploy_gh_release "Palmr" "kyantech/Palmr" "tarball" "latest" "/opt/palmr"

    PNPM="$(jq -r '.packageManager' /opt/palmr/package.json)"
    NODE_VERSION="24" NODE_MODULE="$PNPM" setup_nodejs

    msg_info "Updating ${APP}"
    cd /opt/palmr/apps/server
    mv /opt/palmr.env /opt/palmr/apps/server/.env
    $STD pnpm install
    $STD npx prisma generate
    $STD npx prisma migrate deploy
    $STD npx prisma db push
    $STD pnpm build

    cd /opt/palmr/apps/web
    export NODE_ENV=production
    export NEXT_TELEMETRY_DISABLED=1
    mv ./.env.example ./.env
    $STD pnpm install
    $STD pnpm build
    chown -R palmr:palmr /opt/palmr_data /opt/palmr
    msg_ok "Updated ${APP}"

    msg_info "Starting Services"
    systemctl start palmr-backend palmr-frontend
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
