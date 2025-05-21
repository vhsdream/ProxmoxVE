#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/intri-in/manage-my-damn-life-nextjs

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  mariadb-server
msg_ok "Installed Dependencies"

msg_info "Setting up Database"
DB_NAME=mmdl
DB_USER=mmdl
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD mysql -u root -e "CREATE DATABASE $DB_NAME;"
$STD mysql -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED WITH mysql_native_password AS PASSWORD('$DB_PASS');"
$STD mysql -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
{
  echo "${APPLICATION} Credentials"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
  echo "Database Name: $DB_NAME"
} >>~/"$APP_NAME".creds
msg_ok "Set up Database"

msg_info "Installing NodeJS"
NODE_VERSION="20"
install_node_and_modules
msg_ok "Installed NodeJS"

msg_info "Installing ${APPLICATION}"
RELEASE=$(curl -fsSL https://api.github.com/repos/intri-in/manage-my-damn-life-nextjs/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL -o "${RELEASE}.zip" "https://github.com/intri-in/manage-my-damn-life-nextjs/archive/refs/tags/${RELEASE}.zip"
unzip -q "${RELEASE}.zip"
mv "${APPLICATION}-nextjs-${RELEASE}/" "/opt/mmdl"
cd /opt/mmdl
$STD npm i
cp ./sample.env.local ./.env.local
CALDAV_PASS=$(openssl rand -base64 30)
NEXT_SECRET=$(openssl rand -base64 36)
sed -i "s|db|localhost|; s|myuser|${DB_USER}|; s|mypassword|${DB_PASS}|; s|5433|3306|; s|postgres|mysql|; s|sample_install_mmdm|${DB_NAME}|; \
  s|AES_PASSWORD=PASSWORD|AES_PASSWORD=${CALDAV_PASS}|; s|NEXTAUTH_SECRET=|&\"${NEXT_SECRET}\"|" ./.env.local
$STD npm run migrate
$STD npm run build
echo "${RELEASE}" >/opt/mmdl_version.txt
msg_ok "Installed ${APPLICATION}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/mmdl.service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/mmdl
EnvironmentFile=/opt/mmdl/.env.local
ExecStart=/usr/bin/npm run start
Restart=unless-stopped

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now mmdl.service
msg_ok "Created Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -f "${RELEASE}".zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
