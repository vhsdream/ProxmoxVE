#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/intri-in/manage-my-damn-life-nextjs

APP="Manage My Damn Life"
# Tags for Proxmox VE, maximum 2 pcs., no spaces allowed, separated by a semicolon ; (e.g. database | adblock;dhcp)
var_tags="${var_tags:-caldav}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/mmdl ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Crawling the new version and checking whether an update is required
  RELEASE=$(curl -fsSL https://api.github.com/repos/intri-in/manage-my-damn-life-nextjs/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping $APP"
    systemctl stop mmdl
    msg_ok "Stopped $APP"

    msg_info "Backing up env file"
    cp /opt/"${APP}"/.env.local /opt/mmdl.env
    msg_ok "Backup Created"

    msg_info "Updating $APP to v${RELEASE}"
    rm -r /opt/"${APP}"
    cd /tmp
    curl -fsSL -o "${RELEASE}.zip" "https://github.com/intri-in/manage-my-damn-life-nextjs/archive/refs/tags/${RELEASE}.zip"
    unzip -q "${RELEASE}.zip"
    mv "${APP}-nextjs-${RELEASE}/" "/opt/mmdl"
    cd /opt/mmdl
    $STD npm i
    $STD npm run migrate
    $STD npm run build
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    systemctl start mmdl
    msg_ok "Started $APP"

    msg_info "Cleaning Up"
    rm -rf /tmp/"${RELEASE}".zip
    msg_ok "Cleanup Completed"

    # Last Action
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
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
