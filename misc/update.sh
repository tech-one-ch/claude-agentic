#!/usr/bin/env bash

# Claude Agentic — Standalone updater (curl-able)
# Run inside an LXC or VM (not on the Proxmox host):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/misc/update.sh)"

set -euo pipefail

# Refuse to run on the Proxmox host
if [[ -d /etc/pve ]]; then
  echo "This script must be run inside the LXC or VM, not on the Proxmox host." >&2
  exit 1
fi

[[ $EUID -ne 0 ]] && exec sudo "$0" "$@"

# If the 'update' command is already installed, use it directly
if [[ -x /usr/local/bin/update ]]; then
  exec /usr/local/bin/update
fi

# Fallback: inline update (system not yet set up via installer)
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

echo -e "\n ${BOLD}${YW}Claude Agentic — Update (fallback mode)${CL}"
echo -e " ${YW}Tip: run the installer first to get the persistent 'update' command.${CL}\n"

msg_info "Updating system packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
apt-get autoremove -y -qq
msg_ok "System packages updated"

if command -v claude &>/dev/null; then
  msg_info "Updating Claude Code"
  curl -fsSL https://claude.ai/install.sh | bash \
    || npm update -g @anthropic-ai/claude-code
  msg_ok "Claude Code updated ($(claude --version 2>/dev/null || echo 'latest'))"
else
  msg_error "Claude Code not found — run the installer first"
fi

if command -v code-server &>/dev/null; then
  msg_info "Updating code-server"
  curl -fsSL https://code-server.dev/install.sh | sh
  _cs_svc=$(systemctl list-unit-files 'code-server@*.service' --no-legend 2>/dev/null \
    | awk '$2 ~ /enabled/ {gsub(/\.service$/, "", $1); print $1; exit}')
  [[ -n "$_cs_svc" ]] && systemctl restart "$_cs_svc" 2>/dev/null || true
  msg_ok "code-server updated"
fi

echo -e "\n ${CM} ${BOLD}${GN}All updates applied.${CL}\n"
