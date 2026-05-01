#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/grimmory-tools/grimmory

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y ffmpeg
msg_ok "Installed Dependencies"

JAVA_VERSION="25" setup_java
setup_yq
setup_mariadb
MARIADB_DB_NAME="grimmory" MARIADB_DB_USER="grimmory_usr" setup_mariadb_db

fetch_and_deploy_gh_release "grimmory" "grimmory-tools/grimmory" "singlefile" "latest" "/opt/grimmory/dist"
mv /opt/grimmory/dist/grimmory /opt/grimmory/dist/app.jar

msg_info "Configuring Environment"
mkdir -p /opt/booklore_storage/{books,bookdrop,data}
cat <<EOF >/opt/booklore_storage/.env
DATABASE_URL=jdbc:mariadb://localhost:3306/${MARIADB_DB_NAME}
DATABASE_USERNAME=${MARIADB_DB_USER}
DATABASE_PASSWORD=${MARIDB_DB_PASS}

APP_PATH_CONFIG=/opt/booklore_storage/data
APP_BOOKDROP_FOLDER=/opt/booklore_storage/bookdrop
SERVER_PORT=6060
JAVA_TOOL_OPTIONS="-XX:+UseShenandoahGC \
    -XX:ShenandoahGCHeuristics=compact \
    -XX:+UseCompactObjectHeaders \
    -XX:MaxRAMPercentage=60.0 \
    -XX:InitialRAMPercentage=8.0 \
    -XX:+ExitOnOutOfMemoryError \
    -XX:+HeapDumpOnOutOfMemoryError \
    -XX:HeapDumpPath=/tmp/heapdump.hprof \
    -XX:MaxMetaspaceSize=256m \
    -XX:ReservedCodeCacheSize=48m \
    -Xss512k \
    -XX:CICompilerCount=2 \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+UseStringDeduplication \
    -XX:ShenandoahUncommitDelay=5000 \
    -XX:ShenandoahGuaranteedGCInterval=30000 \
    -XX:MaxDirectMemorySize=256m"
EOF
msg_ok "Configured Environment"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/grimmory.service
[Unit]
Description=Grimmory EBook server
After=network.target mariadb.service

[Service]
User=root
WorkingDirectory=/opt/grimmory/dist
EnvironmentFile=/opt/booklore_storage/.env
ExecStart=/usr/bin/java --enable-native-access=ALL-UNNAMED --enable-preview -jar /opt/grimmory/dist/app.jar
EnvironmentFile=/opt/booklore_storage/.env
SuccessExitStatus=143
TimeoutStopSec=10
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now grimmory
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
