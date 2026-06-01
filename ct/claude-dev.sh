#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: noah-farquet
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.anthropic.com/claude-code

APP="Claude Dev"
var_tags="${var_tags:-claude;development;ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-0}"
var_nesting="${var_nesting:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! $(command -v claude 2>/dev/null) ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Claude Code"
  $STD npm update -g @anthropic-ai/claude-code
  msg_ok "Updated Claude Code ($(claude --version 2>/dev/null || echo 'latest'))"

  msg_info "Updating code-server"
  $STD curl -fsSL https://code-server.dev/install.sh | sh
  $STD systemctl restart code-server@root
  msg_ok "Updated code-server"

  msg_info "Updating System Packages"
  $STD apt-get update
  $STD apt-get upgrade -y
  msg_ok "Updated System Packages"
  exit
}

start
build_container
description

# Disable AppArmor for Docker-in-LXC compatibility
if [[ -f /etc/pve/lxc/${CTID}.conf ]]; then
  if ! grep -q "lxc.apparmor.profile" /etc/pve/lxc/${CTID}.conf; then
    echo "lxc.apparmor.profile: unconfined" >> /etc/pve/lxc/${CTID}.conf
    pct reboot ${CTID} --timeout 10 &>/dev/null || true
    sleep 8
  fi
fi

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Code Server (VS Code in browser):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:8443${CL}"
echo -e "${INFO}${YW} Password is displayed at first container login (MOTD)${CL}"
echo -e "${INFO}${YW} Run Claude Code inside the container:${CL}"
echo -e "${TAB}${BOLD}pct exec ${CTID} -- claude${CL}"
echo -e "${INFO}${YW} Open a shell in the container:${CL}"
echo -e "${TAB}${BOLD}pct enter ${CTID}${CL}"
