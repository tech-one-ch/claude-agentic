#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Craftin535
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.anthropic.com/claude-code
#
# Dual-mode installer:
#   - Called by ct/claude-dev.sh inside a Proxmox LXC (FUNCTIONS_FILE_PATH is set)
#   - Can also run standalone on any existing Debian/Ubuntu system or VPS

# ─── Mode detection ────────────────────────────────────────────────────────────

if [[ -n "$FUNCTIONS_FILE_PATH" ]]; then
  # Community-scripts context: functions injected by Proxmox host
  source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os
else
  # Standalone mode: define minimal compatible functions
  YW=$(printf '\033[33m')
  GN=$(printf '\033[1;92m')
  RD=$(printf '\033[01;31m')
  BL=$(printf '\033[36m')
  BOLD=$(printf '\033[1m')
  CL=$(printf '\033[m')
  BFR="\\r\\033[K"
  CM="${GN}✔${CL}"
  CROSS="${RD}✖${CL}"
  INFO="${BL}ℹ${CL}"

  msg_info()  { local m="$1"; echo -ne " ⏳ ${YW}${m}...${CL}"; }
  msg_ok()    { local m="$1"; echo -e "${BFR} ${CM} ${GN}${m}${CL}"; }
  msg_error() { local m="$1"; echo -e "${BFR} ${CROSS} ${RD}${m}${CL}"; exit 1; }
  msg_warn()  { local m="$1"; echo -e " ${INFO} ${YW}${m}${CL}"; }

  [[ $EUID -ne 0 ]] && msg_error "Run as root: sudo bash install/claude-dev-install.sh"
  [[ ! -f /etc/os-release ]] && msg_error "Cannot detect OS"
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ "$ID" != "debian" && "$ID" != "ubuntu" ]] && msg_error "Requires Debian or Ubuntu (got: ${ID})"

  STD=""  # Show full output in standalone mode

  echo -e "\n ${BOLD}${BL}Claude Dev — Standalone Installer${CL}"
  echo -e " ${YW}OS: ${ID} ${VERSION_ID}${CL}\n"

  msg_info "Updating system packages"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
  msg_ok "System updated"
fi

APP="${APP:-Claude Dev}"

# ─── 1. Base dependencies ───────────────────────────────────────────────────────

msg_info "Installing base dependencies"
$STD apt-get install -y \
  curl wget git build-essential pkg-config \
  ca-certificates gnupg lsb-release apt-transport-https \
  software-properties-common \
  libssl-dev libffi-dev zlib1g-dev libbz2-dev libreadline-dev \
  libsqlite3-dev libncursesw5-dev libgdbm-dev liblzma-dev libxml2-dev \
  tmux htop nano vim jq unzip zip tar openssl \
  ripgrep fd-find fzf \
  postgresql-client sqlite3 redis-tools
msg_ok "Installed base dependencies"

# bat (binary is batcat on Debian/Ubuntu, symlink to bat)
msg_info "Installing bat"
$STD apt-get install -y bat 2>/dev/null || $STD apt-get install -y batcat 2>/dev/null || true
[[ ! -f /usr/local/bin/bat ]] && [[ -f /usr/bin/batcat ]] && ln -s /usr/bin/batcat /usr/local/bin/bat
msg_ok "Installed bat"

# fd symlink (binary is fdfind on Debian/Ubuntu)
[[ ! -f /usr/local/bin/fd ]] && [[ -f /usr/bin/fdfind ]] && ln -s /usr/bin/fdfind /usr/local/bin/fd

# ─── 2. Node.js 22 LTS ──────────────────────────────────────────────────────────

msg_info "Installing Node.js 22 LTS"
$STD curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node --version)"

# ─── 3. Python 3 + tools ────────────────────────────────────────────────────────

msg_info "Installing Python tools"
$STD apt-get install -y python3 python3-pip python3-venv python3-dev
$STD pip3 install --quiet pipx uv 2>/dev/null || true
msg_ok "Installed Python $(python3 --version | cut -d' ' -f2)"

# ─── 4. Go (latest) ─────────────────────────────────────────────────────────────

msg_info "Installing Go"
GO_VERSION=$(curl -fsS "https://go.dev/dl/?mode=json" | grep -o '"version":"go[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$GO_VERSION" ]]; then
  $STD curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz
  rm -rf /usr/local/go
  $STD tar -C /usr/local -xzf /tmp/go.tar.gz
  rm -f /tmp/go.tar.gz
  [[ ! -f /usr/local/bin/go ]] && ln -s /usr/local/go/bin/go /usr/local/bin/go
  [[ ! -f /usr/local/bin/gofmt ]] && ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  msg_ok "Installed Go ${GO_VERSION}"
else
  msg_warn "Could not determine latest Go version, skipping"
fi

# ─── 5. Rust ────────────────────────────────────────────────────────────────────

msg_info "Installing Rust"
$STD curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --quiet
export PATH="/root/.cargo/bin:$PATH"
[[ ! -f /usr/local/bin/cargo ]] && ln -s /root/.cargo/bin/cargo /usr/local/bin/cargo 2>/dev/null || true
[[ ! -f /usr/local/bin/rustc ]] && ln -s /root/.cargo/bin/rustc /usr/local/bin/rustc 2>/dev/null || true
msg_ok "Installed Rust $(rustc --version 2>/dev/null | cut -d' ' -f2 || echo 'latest')"

# ─── 6. Docker + Docker Compose ─────────────────────────────────────────────────

msg_info "Installing Docker"
$STD curl -fsSL https://get.docker.com | sh
$STD systemctl enable --now docker
$STD curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
msg_ok "Installed Docker $(docker --version | cut -d' ' -f3 | tr -d ',')"

# Watchtower: auto-update Docker containers
msg_info "Starting Watchtower (Docker auto-updater)"
$STD docker run -d \
  --name watchtower \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --cleanup --interval 86400
msg_ok "Watchtower running"

# ─── 7. code-server (VS Code in browser) ─────────────────────────────────────────

msg_info "Installing code-server"
$STD curl -fsSL https://code-server.dev/install.sh | sh

CS_PASSWORD=$(openssl rand -hex 16)
mkdir -p /root/.config/code-server
cat > /root/.config/code-server/config.yaml <<EOF
bind-addr: 0.0.0.0:8443
auth: password
password: ${CS_PASSWORD}
cert: true
EOF

systemctl enable --now code-server@root &>/dev/null || true
msg_ok "Installed code-server (port 8443)"

# ─── 8. Claude Code ─────────────────────────────────────────────────────────────

msg_info "Installing Claude Code"
$STD npm install -g @anthropic-ai/claude-code
msg_ok "Installed Claude Code $(claude --version 2>/dev/null || echo 'latest')"

msg_info "Configuring Claude Code permissions"
mkdir -p /root/.claude
cat > /root/.claude/settings.json <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "WebFetch(*)",
      "WebSearch(*)",
      "Task(*)",
      "Agent(*)",
      "TodoWrite(*)",
      "TodoRead(*)"
    ],
    "deny": []
  },
  "enabledFeatures": {
    "agentTeams": true
  },
  "env": {
    "ANTHROPIC_MODEL": "claude-sonnet-4-6"
  }
}
EOF
msg_ok "Configured Claude Code (all permissions pre-approved)"

# ─── 9. GitHub CLI ───────────────────────────────────────────────────────────────

msg_info "Installing GitHub CLI (gh)"
$STD curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
$STD apt-get update
$STD apt-get install -y gh
msg_ok "Installed GitHub CLI $(gh --version | head -1 | cut -d' ' -f3)"

# ─── 10. Shell environment ──────────────────────────────────────────────────────

msg_info "Configuring shell environment"
cat >> /root/.bashrc <<'EOF'

# Claude Dev environment
export PATH="/root/.cargo/bin:/usr/local/go/bin:$PATH"
export GOPATH="/root/go"
export PATH="$GOPATH/bin:$PATH"

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias ..='cd ..'
alias dc='docker compose'
alias k='kubectl'
EOF
msg_ok "Shell environment configured"

# ─── 11. Scheduled updates ──────────────────────────────────────────────────────

msg_info "Setting up weekly auto-update"
cat > /etc/cron.weekly/claude-dev-update <<'CRON'
#!/usr/bin/env bash
apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
npm update -g @anthropic-ai/claude-code 2>/dev/null || true
curl -fsSL https://code-server.dev/install.sh | sh 2>/dev/null || true
systemctl restart code-server@root 2>/dev/null || true
CRON
chmod +x /etc/cron.weekly/claude-dev-update
msg_ok "Weekly auto-update scheduled"

# ─── 12. MOTD with credentials ──────────────────────────────────────────────────

msg_info "Writing login banner"
SERVER_IP=$(hostname -I | awk '{print $1}')
cat > /etc/motd <<EOF

  ╔═══════════════════════════════════════════════════════╗
  ║              Claude Dev Environment                   ║
  ╠═══════════════════════════════════════════════════════╣
  ║  Code Server:  https://${SERVER_IP}:8443
  ║  Password:     ${CS_PASSWORD}
  ║                                                       ║
  ║  Start Claude: claude                                 ║
  ║  Projects dir: /root/projects                         ║
  ╚═══════════════════════════════════════════════════════╝

EOF
mkdir -p /root/projects
msg_ok "Login banner configured"

# ─── Done ────────────────────────────────────────────────────────────────────────

if [[ -n "$FUNCTIONS_FILE_PATH" ]]; then
  motd_ssh
  customize
  cleanup_lxc
else
  echo -e "\n ${CM} ${BOLD}${GN}Installation complete!${CL}\n"
  echo -e "  ${INFO} Code Server: ${BOLD}https://${SERVER_IP}:8443${CL}"
  echo -e "  ${INFO} Password:    ${BOLD}${CS_PASSWORD}${CL}"
  echo -e "  ${INFO} Claude Code: ${BOLD}claude${CL} (run in terminal)\n"
  echo -e "  ${YW}Note: Set your API key before using Claude:${CL}"
  echo -e "  ${BOLD}export ANTHROPIC_API_KEY='sk-ant-...'${CL}\n"
fi
