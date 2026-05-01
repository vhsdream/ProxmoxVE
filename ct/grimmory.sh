#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/vhsdream/ProxmoxVE/refs/heads/grimmory-dev/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ) | jferdom | vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/grimmory-tools/grimmory

APP="Grimmory"
var_tags="${var_tags:-books;library}"
var_cpu="${var_cpu:-3}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-7}"
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

  if [[ ! -d /opt/booklore ]]; then
    if [[ ! -d /opt/grimmory ]]; then
      msg_error "No BookLore or ${APP} Installation Found!"
      exit
    fi
  fi

  if check_for_gh_release "grimmory" "grimmory-tools/grimmory"; then
    JAVA_VERSION="25" setup_java
    setup_mariadb
    setup_yq
    ensure_dependencies ffmpeg

    msg_info "Stopping Service"
    if [[ -d /opt/grimmory ]]; then
      systemctl stop grimmory
    else
      systemctl stop booklore
    fi
    msg_ok "Stopped Service"

    if [[ -d /opt/booklore ]]; then
      msg_warn "Migrating booklore to grimmory"
    fi

    if grep -qE "^BOOKLORE_(DATA_PATH|BOOKDROP_PATH|BOOKS_PATH|PORT)=" /opt/booklore_storage/.env 2>/dev/null; then
      msg_info "Migrating old environment variables"
      sed -i -e 's/^BOOKLORE_DATA_PATH=/APP_PATH_CONFIG=/g' \
        -e 's/^BOOKLORE_BOOKDROP_PATH=/APP_BOOKDROP_FOLDER=/g' \
        -e '/^BOOKLORE_BOOKS_PATH=/d' \
        -e '/^BOOKLORE_PORT=/d' /opt/booklore_storage/.env
      msg_ok "Migrated old environment variables"
    fi

    msg_info "Backing up old installation"
    if [[ -d /opt/grimmory ]]; then
      mv /opt/grimmory /opt/grimmory_bak
    else
      mv /opt/booklore /opt/booklore_bak
    fi
    msg_ok "Backed up old installation"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "grimmory" "grimmory-tools/grimmory" "singlefile" "latest" "/opt/grimmory/dist" "grimmory-v*.jar"
    mv /opt/grimmory/dist/grimmory /opt/grimmory/dist/app.jar

    if [[ -f /opt/booklore_storage/data/tools/kepubify/kepubify-linux-64bit ]]; then
      msg_info "Migrating Kepubify to /usr/local/bin"
      mv /opt/booklore_storage/data/tools/kepubify/kepubify-linux-64bit /usr/local/bin/kepubify
      msg_ok "Migrated Kepubify to /usr/local/bin"
    fi

    if systemctl is-active --quiet nginx 2>/dev/null; then
      msg_info "Removing Nginx (no longer needed)"
      systemctl disable --now nginx
      $STD apt-get purge -y nginx nginx-common
      msg_ok "Removed Nginx"
    fi

    if [[ -f /etc/apt/sources.list.d/nodesource.sources ]]; then
      msg_info "Removing NodeJS (no longer needed)"
      $STD apt-get purge -y nodejs
      msg_ok "Removed NodeJS"
    fi

    if ! grep -q "^SERVER_PORT=" /opt/booklore_storage/.env 2>/dev/null; then
      echo "SERVER_PORT=6060" >>/opt/booklore_storage/.env
    fi

    if ! grep -q "JAVA_TOOL" /opt/booklore_storage/.env; then
      {
        echo ""
        echo 'JAVA_TOOL_OPTIONS="-XX:+UseShenandoahGC \
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
          -XX:MaxDirectMemorySize=256m"'
      } >>/opt/booklore_storage/.env
    fi

    if test -f /etc/systemd/system/booklore.service; then
      mv /etc/systemd/system/booklore.service /etc/systemd/system/grimmory.service
      sed -i -e 's|WorkingDirectory=.*|WorkingDirectory=/opt/grimmory/dist|' \
        -e '\|dist$|a EnvironmentFile=/opt/booklore_storage/.env' \
        -e 's|ExecStart=.*|ExecStart=/usr/bin/java --enable-native-access=ALL-UNNAMED --enable-preview -jar /opt/grimmory/dist/app.jar|' /etc/systemd/system/grimmory.service
      systemctl daemon-reload
      systemctl -q enable grimmory
    fi

    msg_info "Starting Service"
    systemctl start grimmory
    if [[ -d /opt/grimmory_bak ]]; then
      rm -rf /opt/grimmory_bak
    fi

    if [[ -d /opt/booklore_bak ]]; then
      rm -rf /opt/booklore_bak
    fi
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6060${CL}"
