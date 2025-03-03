#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/crocodilestick/Calibre-Web-Automated

# Import Functions und Setup
source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies with the 3 core dependencies (curl;sudo;mc)
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  build-essential \
  imagemagick \
  git \
  libldap2-dev \
  libsasl2-dev \
  ghostscript \
  libldap-2.5-0 \
  libmagic1 \
  libsasl2-2 \
  libxi6 \
  libxslt1.1 \
  python3-pip \
  python3-venv \
  xdg-utils \
  inotify-tools \
  sqlite3
msg_ok "Installed Dependencies"

msg_info "Installing Kepubify"
mkdir -p /opt/kepubify
cd /opt/kepubify
curl -fsSLO https://github.com/pgaskin/kepubify/releases/latest/download/kepubify-linux-64bit &>/dev/null
chmod +x kepubify-linux-64bit
msg_ok "Installed Kepubify"

msg_info "Installing Calibre-Web"
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
mkdir -p /opt/calibre-web
$STD apt-get install -y calibre
$STD wget https://github.com/janeczku/calibre-web/raw/master/library/metadata.db -P /opt/calibre-web
$STD pip install calibreweb[goodreads,metadata,kobo]
$STD pip install jsonschema
msg_ok "Installed Calibre-Web"

msg_info "Setup ${APPLICATION}"
RELEASE=$(curl -s https://api.github.com/repos/crocodilestick/Calibre-Web-Automated/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
$STD git clone https://github.com/crocodilestick/Calibre-Web-Automated.git /opt/cwa --single-branch
cd /opt/cwa
$STD git checkout V${RELEASE}
$STD pip install -r requirements.txt
# The following is NOT for production! Must find another way before making a PR!
wget -q https://raw.githubusercontent.com/vhsdream/cwa-lxc/refs/heads/git-patch/proxmox-lxc.patch -O /opt/cwa.patch
$STD git apply /opt/cwa.patch
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Setup ${APPLICATION}"

msg_info "Creating necessary files & directories"
mkdir -p /opt/cwa/{metadata_change_logs,metadata_temp}
mkdir -p /opt/cwa-book-ingest
mkdir -p /var/lib/cwa/{processed_books,log_archive,.cwa_conversion_tmp}
mkdir -p /var/lib/cwa/processed_books/{converted,imported,failed,fixed_originals}
touch /var/lib/cwa/convert-library.log
msg_ok "Directories & files created"

msg_info "Copying patched Calibre-Web files into local Python lib folder"
cp -r /opt/cwa/root/app/calibre-web/cps/* /usr/local/lib/python3.11/dist-packages/calibreweb/cps
msg_ok "Files copied"

msg_info "Creating Services and Timers"
cat <<EOF >/etc/systemd/system/cps.service
[Unit]
Description=Calibre-Web Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/calibre-web
ExecStart=/usr/local/bin/cps
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/cwa-autolibrary.service
[Unit]
Description=Calibre-Web Automated Auto-Library Service
After=network.target cps.service

[Service]
Type=simple
WorkingDirectory=/opt/cwa
ExecStart=/usr/bin/python3 /opt/cwa/scripts/auto_library.py
TimeoutStopSec=10
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/cwa-ingester.service
[Unit]
Description=Calibre-Web Automated Ingest Service
After=network.target cps.service cwa-autolibrary.service

[Service]
Type=simple
WorkingDirectory=/opt/cwa
ExecStart=/usr/bin/bash -c /opt/cwa/scripts/ingest-service.sh
TimeoutStopSec=10
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/cwa-change-detector.service
[Unit]
Description=Calibre-Web Automated Metadata Change Detector Service
After=network.target cps.service cwa-autolibrary.service

[Service]
Type=simple
WorkingDirectory=/opt/cwa
ExecStart=/usr/bin/bash -c /opt/cwa/scripts/change-detector.sh
TimeoutStopSec=10
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/cwa.target
[Unit]
Description=Calibre-Web Automated Services
After=network-online.target
Wants=cps.service cwa-autolibrary.service cwa-ingester.service cwa-change-detector.service cwa-autozip.timer

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/cwa-autozip.service
[Unit]
Description=Calibre-Web Automated Nightly Auto-Zip Backup Service
After=network.target cps.service

[Service]
Type=simple
WorkingDirectory=/var/lib/cwa/processed_books
ExecStart=/usr/bin/python3 /opt/cwa/scripts/auto_zip.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/cwa-autozip.timer
[Unit]
Description=Calibre-Web Automated Nightly Auto-Zip Backup Timer
RefuseManualStart=no
RefuseManualStop=no

[Timer]
Persistent=true
# run every day at 11:59PM
OnCalendar=*-*-* 23:59:00
Unit=cwa-autozip.service

[Install]
WantedBy=timers.target
EOF
systemctl enable -q --now cwa.target
msg_ok "Created Services and Timers"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -rf /opt/cwa.patch
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
