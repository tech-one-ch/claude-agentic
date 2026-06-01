#!/usr/bin/env bash

# Standalone update script for existing Claude Dev installations
# Works on any Debian/Ubuntu system where install/claude-dev-install.sh was run

set -euo pipefail

YW=$(printf '\033[33m')
GN=$(printf '\033[1;92m')
RD=$(printf '\033[01;31m')
BOLD=$(printf '\033[1m')
CL=$(printf '\033[m')
BFR="\\r\\033[K"
CM="${GN}✔${CL}"
CROSS="${RD}✖${CL}"

msg_info()  { local m="$1"; echo -ne " ⏳ ${YW}${m}...${CL}"; }
msg_ok()    { local m="$1"; echo -e "${BFR} ${CM} ${GN}${m}${CL}"; }
msg_error() { local m="$1"; echo -e "${BFR} ${CROSS} ${RD}${m}${CL}"; exit 1; }

[[ $EUID -ne 0 ]] && msg_error "Run as root: sudo bash misc/update.sh"

echo -e "\n ${BOLD}${YW}Claude Dev — Update${CL}\n"

msg_info "Updating system packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
msg_ok "System packages updated"

if command -v claude &>/dev/null; then
  msg_info "Updating Claude Code"
  npm update -g @anthropic-ai/claude-code
  msg_ok "Claude Code updated ($(claude --version 2>/dev/null || echo 'latest'))"
else
  msg_error "Claude Code not found — run the installer first"
fi

if command -v code-server &>/dev/null; then
  msg_info "Updating code-server"
  curl -fsSL https://code-server.dev/install.sh | sh -s -- --dry-run &>/dev/null
  curl -fsSL https://code-server.dev/install.sh | sh
  systemctl restart code-server@root 2>/dev/null || true
  msg_ok "code-server updated"
fi

if command -v docker &>/dev/null; then
  msg_info "Pulling latest Docker images"
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | xargs -r docker pull &>/dev/null || true
  msg_ok "Docker images updated"
fi

echo -e "\n ${CM} ${BOLD}${GN}All updates applied.${CL}\n"
