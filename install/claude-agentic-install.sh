#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Craftin535
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.anthropic.com/claude-code
#
# Dual-mode installer:
#   - Called by ct/claude-agentic.sh inside a Proxmox LXC (FUNCTIONS_FILE_PATH is set)
#   - Can also run standalone on any existing Debian/Ubuntu system or VPS

# ─── Mode detection & logging ──────────────────────────────────────────────────

LOG_FILE="/var/log/claude-agentic-install.log"

if [[ -n "$FUNCTIONS_FILE_PATH" ]]; then
  # community-scripts mode:
  # - commands run normally, output goes to stdout (captured by build.func)
  # - log_run is a transparent pass-through — no redirection, no interference
  log_run() { "$@"; }
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "=== Install started: $(date) ===" >> "$LOG_FILE"
  source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os
else
  # standalone mode — escalate first, before any operation that needs root
  [[ $EUID -ne 0 ]] && exec sudo "$0" "$@"

  mkdir -p "$(dirname "$LOG_FILE")"
  echo "=== Install started: $(date) ===" >> "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
  # log_run redirects output to log file only (screen stays clean)
  log_run() { "$@" >>"$LOG_FILE" 2>&1; }

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
  [[ ! -f /etc/os-release ]] && msg_error "Cannot detect OS"
  source /etc/os-release
  [[ "$ID" != "debian" && "$ID" != "ubuntu" ]] && msg_error "Requires Debian or Ubuntu (got: ${ID})"

  echo -e "\n ${BOLD}${BL}Claude Agentic — Standalone Installer${CL}"
  echo -e " ${YW}OS: ${ID} ${VERSION_ID}${CL}"
  echo -e " ${YW}Log: ${LOG_FILE}${CL}\n"

  msg_info "Updating system packages"
  log_run apt-get update
  log_run env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  msg_ok "System updated"
fi

APP="${APP:-Claude Agentic}"

# ─── User context ──────────────────────────────────────────────────────────────
# LXC / direct root  : SUDO_USER unset  → REAL_USER=root, REAL_HOME=/root
# VM via sudo        : SUDO_USER=alice  → REAL_USER=alice, REAL_HOME=/home/alice
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  REAL_USER="$SUDO_USER"
  REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
  REAL_USER="root"
  REAL_HOME="/root"
fi

# Run a command as REAL_USER with their HOME set (no-op wrapper when already root)
run_as_user() {
  if [[ "$REAL_USER" == "root" ]]; then
    "$@"
  else
    env HOME="$REAL_HOME" su "$REAL_USER" -c "$(printf '%q ' "$@")"
  fi
}

# ─── Configuration ─────────────────────────────────────────────────────────────
# Default IDE when no input is given (timeout or non-interactive mode)
# Options: codeserver | tunnel | both | none
DEFAULT_IDE_CHOICE="both"

# ─── IDE choice ────────────────────────────────────────────────────────────────
# IDE_CHOICE: codeserver | tunnel | both | none
# In community-scripts mode: set via environment variable before running
# In standalone mode: interactive prompt

if [[ -z "${IDE_CHOICE:-}" ]]; then
  if [[ -t 0 ]]; then
    echo -e "\n ${BOLD}Web IDE${CL}"
    echo "  1) code-server   — VS Code in browser (port 8443)"
    echo "  2) VS Code Tunnel — Microsoft relay (vscode.dev, no open port)"
    echo "  3) Both"
    echo "  4) None"
    read -rt 60 -p "  Choice [default: ${DEFAULT_IDE_CHOICE}, 60s timeout]: " _ide_input || true
    case "${_ide_input:-}" in
      1) IDE_CHOICE="codeserver" ;;
      2) IDE_CHOICE="tunnel" ;;
      3) IDE_CHOICE="both" ;;
      4) IDE_CHOICE="none" ;;
      *) IDE_CHOICE="$DEFAULT_IDE_CHOICE" ;;
    esac
  else
    IDE_CHOICE="$DEFAULT_IDE_CHOICE"
  fi
fi

# ─── 1. Locale ──────────────────────────────────────────────────────────────────

msg_info "Configuring locale"
log_run apt-get install -y locales
sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen
log_run locale-gen en_US.UTF-8
log_run update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
msg_ok "Locale configured (en_US.UTF-8)"

# ─── 2. Base dependencies ────────────────────────────────────────────────────────

msg_info "Installing base dependencies"
log_run apt-get install -y \
  curl wget git build-essential make cmake pkg-config autoconf automake libtool \
  ca-certificates gnupg lsb-release apt-transport-https software-properties-common \
  libssl-dev libffi-dev zlib1g-dev libbz2-dev libreadline-dev \
  libsqlite3-dev libncursesw5-dev libgdbm-dev liblzma-dev libxml2-dev libxslt-dev \
  tmux screen htop nano vim jq yq unzip zip tar openssl \
  ripgrep fzf \
  net-tools iproute2 dnsutils openssh-server \
  postgresql-client sqlite3 redis-tools \
  cron logrotate
msg_ok "Installed base dependencies"

# fd: Ubuntu's fd-find package installs a broken symlink. Install the static binary directly.
# Version detection via redirect (not the GitHub API — avoids the 60 req/h rate limit).
msg_info "Installing fd"
_fd_ver=$(curl -fsL -o /dev/null -w '%{url_effective}' \
  "https://github.com/sharkdp/fd/releases/latest" 2>/dev/null \
  | sed 's|.*/tag/||' || true)
if [[ -n "$_fd_ver" ]]; then
  curl -fsSL "https://github.com/sharkdp/fd/releases/download/${_fd_ver}/fd-${_fd_ver}-x86_64-unknown-linux-musl.tar.gz" \
    -o /tmp/_fd.tar.gz
  mkdir -p /tmp/_fd_tmp
  tar -xzf /tmp/_fd.tar.gz -C /tmp/_fd_tmp --strip-components=1
  mv /tmp/_fd_tmp/fd /usr/local/bin/fd
  chmod 0755 /usr/local/bin/fd
  chown 0:0 /usr/local/bin/fd
  ln -sf /usr/local/bin/fd /usr/bin/fd
  rm -rf /tmp/_fd.tar.gz /tmp/_fd_tmp
  msg_ok "Installed fd ${_fd_ver}"
else
  msg_warn "Could not resolve fd version (network issue?) — fd not installed"
fi

# bat: Ubuntu apt installs as 'batcat' (name conflict). Install the static binary directly.
msg_info "Installing bat"
_bat_ver=$(curl -fsL -o /dev/null -w '%{url_effective}' \
  "https://github.com/sharkdp/bat/releases/latest" 2>/dev/null \
  | sed 's|.*/tag/||' || true)
if [[ -n "$_bat_ver" ]]; then
  curl -fsSL "https://github.com/sharkdp/bat/releases/download/${_bat_ver}/bat-${_bat_ver}-x86_64-unknown-linux-musl.tar.gz" \
    -o /tmp/_bat.tar.gz
  mkdir -p /tmp/_bat_tmp
  tar -xzf /tmp/_bat.tar.gz -C /tmp/_bat_tmp --strip-components=1
  mv /tmp/_bat_tmp/bat /usr/local/bin/bat
  chmod 0755 /usr/local/bin/bat
  chown 0:0 /usr/local/bin/bat
  ln -sf /usr/local/bin/bat /usr/bin/bat
  rm -rf /tmp/_bat.tar.gz /tmp/_bat_tmp
  msg_ok "Installed bat ${_bat_ver}"
else
  msg_warn "Could not resolve bat version (network issue?) — bat not installed"
fi

# ─── 3. Node.js 22 LTS ───────────────────────────────────────────────────────────

msg_info "Installing Node.js 22 LTS"
curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/_nodesource_setup.sh
log_run bash /tmp/_nodesource_setup.sh
rm -f /tmp/_nodesource_setup.sh
log_run apt-get install -y nodejs
msg_ok "Installed Node.js $(node --version)"

msg_info "Installing global Node.js tools"
log_run npm install -g typescript ts-node eslint prettier
msg_ok "Installed TypeScript, ts-node, ESLint, Prettier"

# ─── 4. Python 3 ─────────────────────────────────────────────────────────────────

msg_info "Installing Python tools"
log_run apt-get install -y python3 python3-pip python3-venv python3-dev
log_run pip3 install --quiet --break-system-packages pipx uv 2>/dev/null || \
  log_run pip3 install --quiet pipx uv 2>/dev/null || true
msg_ok "Installed Python $(python3 --version | cut -d' ' -f2)"

# ─── 5. Go (latest) ──────────────────────────────────────────────────────────────

msg_info "Installing Go"
GO_VERSION=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -1)
if [[ -n "$GO_VERSION" ]]; then
  log_run curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz
  rm -rf /usr/local/go
  log_run tar -C /usr/local -xzf /tmp/go.tar.gz
  rm -f /tmp/go.tar.gz
  # Symlinks in /usr/local/bin so go is available in all shells (not just login shells)
  ln -sf /usr/local/go/bin/go    /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  cat > /etc/profile.d/go.sh <<'EOF'
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF
  msg_ok "Installed Go ${GO_VERSION}"
else
  msg_warn "Could not fetch Go version, skipping"
fi

# ─── 6. Rust ──────────────────────────────────────────────────────────────────────

msg_info "Installing Rust"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/_rustup_init.sh
log_run run_as_user sh /tmp/_rustup_init.sh -y --no-modify-path
rm -f /tmp/_rustup_init.sh
source "$REAL_HOME/.cargo/env" 2>/dev/null || export PATH="$REAL_HOME/.cargo/bin:$PATH"
[[ ! -f /usr/local/bin/cargo ]] && ln -sf "$REAL_HOME/.cargo/bin/cargo" /usr/local/bin/cargo 2>/dev/null || true
[[ ! -f /usr/local/bin/rustc ]] && ln -sf "$REAL_HOME/.cargo/bin/rustc" /usr/local/bin/rustc 2>/dev/null || true
ln -sf /usr/local/bin/cargo /usr/bin/cargo 2>/dev/null || true
ln -sf /usr/local/bin/rustc /usr/bin/rustc 2>/dev/null || true
msg_ok "Installed Rust $(rustc --version 2>/dev/null | cut -d' ' -f2 || echo 'latest')"

# ─── 7. Docker + Compose plugin ───────────────────────────────────────────────────

msg_info "Installing Docker"
curl -fsSL https://get.docker.com -o /tmp/_docker_install.sh
log_run sh /tmp/_docker_install.sh
rm -f /tmp/_docker_install.sh
log_run systemctl enable --now docker
log_run apt-get install -y docker-compose-plugin
msg_ok "Installed Docker $(docker --version | cut -d' ' -f3 | tr -d ',') + Compose plugin"

# ─── 8. GitHub CLI ────────────────────────────────────────────────────────────────

msg_info "Installing GitHub CLI"
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
log_run apt-get update
log_run apt-get install -y gh
msg_ok "Installed GitHub CLI $(gh --version | head -1 | cut -d' ' -f3)"

# ─── 9. Web IDE ───────────────────────────────────────────────────────────────────

CS_PASSWORD=""

if [[ "$IDE_CHOICE" == "codeserver" || "$IDE_CHOICE" == "both" ]]; then
  msg_info "Installing code-server"
  curl -fsSL https://code-server.dev/install.sh -o /tmp/_codeserver_install.sh
  log_run sh /tmp/_codeserver_install.sh
  rm -f /tmp/_codeserver_install.sh
  CS_PASSWORD=$(openssl rand -hex 16)
  mkdir -p "$REAL_HOME/.config/code-server"
  cat > "$REAL_HOME/.config/code-server/config.yaml" <<EOF
bind-addr: 0.0.0.0:8443
auth: password
password: ${CS_PASSWORD}
cert: true
EOF
  [[ "$REAL_USER" != "root" ]] && chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/code-server"
  systemctl enable --now "code-server@$REAL_USER" &>/dev/null || true
  msg_ok "Installed code-server (port 8443)"
fi

if [[ "$IDE_CHOICE" == "tunnel" || "$IDE_CHOICE" == "both" ]]; then
  msg_info "Installing VS Code Tunnel CLI (~65 MB, may take a few minutes)"
  _vscode_ok=0
  if curl -fL 'https://update.code.visualstudio.com/latest/cli-linux-x64/stable' \
      -o /tmp/vscode-cli.tar.gz >>"$LOG_FILE" 2>&1 \
    && tar -tzf /tmp/vscode-cli.tar.gz >>"$LOG_FILE" 2>&1; then
    # Extract to a temp dir then locate the 'code' binary regardless of archive structure
    mkdir -p /tmp/_vscode_tmp
    tar -xzf /tmp/vscode-cli.tar.gz -C /tmp/_vscode_tmp/ >>"$LOG_FILE" 2>&1 || true
    _code_bin=$(find /tmp/_vscode_tmp -name code -type f 2>/dev/null | head -1)
    if [[ -n "$_code_bin" ]]; then
      mv "$_code_bin" /usr/local/bin/code
      chmod 0755 /usr/local/bin/code
      chown 0:0 /usr/local/bin/code
      ln -sf /usr/local/bin/code /usr/bin/code
      # Verify the binary actually works — log result for diagnostics
      echo "=== VS Code CLI smoke-test ===" >>"$LOG_FILE"
      /usr/local/bin/code --version >>"$LOG_FILE" 2>&1 && _vscode_ok=1 || {
        echo "code --version exit $? — binary may need unprivileged_userns_clone" >>"$LOG_FILE"
        # Some kernels disable unprivileged user namespaces; enable it so VS Code tunnel can sandbox
        if [[ -f /proc/sys/kernel/unprivileged_userns_clone ]]; then
          echo 1 > /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || true
          sysctl -w kernel.unprivileged_userns_clone=1 >>"$LOG_FILE" 2>&1 || true
          # Persist across reboots
          echo "kernel.unprivileged_userns_clone=1" > /etc/sysctl.d/99-vscode-tunnel.conf
        fi
        /usr/local/bin/code --version >>"$LOG_FILE" 2>&1 && _vscode_ok=1 || \
          echo "code --version still failed after sysctl fix — exit $?" >>"$LOG_FILE"
      }
    fi
    rm -rf /tmp/vscode-cli.tar.gz /tmp/_vscode_tmp
  else
    rm -f /tmp/vscode-cli.tar.gz
  fi
  if [[ $_vscode_ok -eq 1 ]]; then
    msg_ok "Installed VS Code Tunnel — run 'code tunnel' once to authenticate (GitHub or Microsoft account)"
  else
    msg_warn "VS Code Tunnel install failed — check $LOG_FILE for details"
  fi
fi

# ─── 10. Claude Code ──────────────────────────────────────────────────────────────

msg_info "Installing Claude Code"
if [[ "$REAL_USER" == "root" ]]; then
  curl -fsSL https://claude.ai/install.sh | bash >>"$LOG_FILE" 2>&1 \
    || log_run npm install -g @anthropic-ai/claude-code
else
  env HOME="$REAL_HOME" su "$REAL_USER" -c \
    'curl -fsSL https://claude.ai/install.sh | bash' >>"$LOG_FILE" 2>&1 \
    || log_run run_as_user npm install -g @anthropic-ai/claude-code
fi
# The official installer puts the binary in ~/.local/bin — export immediately so it's
# available for the rest of this script and not just in future login shells.
export PATH="$REAL_HOME/.local/bin:$PATH"
msg_ok "Installed Claude Code $(claude --version 2>/dev/null || echo 'latest')"

msg_info "Configuring Claude Code"
mkdir -p "$REAL_HOME/.claude"
cat > "$REAL_HOME/.claude/settings.json" <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "MultiEdit(*)",
      "WebFetch(*)",
      "WebSearch(*)",
      "Task(*)",
      "Agent(*)",
      "TodoWrite(*)",
      "TodoRead(*)",
      "Grep(*)",
      "Glob(*)",
      "LS(*)",
      "mcp__*"
    ],
    "deny": []
  },
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "64000"
  },
  "alwaysThinkingEnabled": true,
  "disableRemoteControl": false
}
EOF
msg_ok "Configured Claude Code (all permissions pre-approved)"
[[ "$REAL_USER" != "root" ]] && chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.claude"

# ─── 11. Workspace & CLAUDE.md ────────────────────────────────────────────────────

msg_info "Setting up workspace"
mkdir -p /project
[[ "$REAL_USER" != "root" ]] && chown "$REAL_USER:$REAL_USER" /project
cat > /project/CLAUDE.md <<'EOF'
# Claude Agentic Workspace

## Environment
- **OS**: Ubuntu 24.04 (LXC on Proxmox or standalone VM/VPS)
- **Working directory**: /project
- **User**: root

## Available tools
- **Languages**: Node.js 22 LTS, TypeScript, Python 3, Go (latest), Rust (latest)
- **Package managers**: npm, pip (--break-system-packages), cargo, go install
- **Docker**: Docker Engine + Compose plugin (`docker compose`)
- **GitHub**: `gh` CLI pre-installed — use it for PRs, issues, releases
- **Search**: ripgrep (`rg`), fd, fzf, bat, jq, yq
- **Databases**: PostgreSQL client, Redis CLI, SQLite3
- **Editor**: code-server on port 8443 (VS Code in browser) — run 'code tunnel' once to also enable VS Code Tunnel (vscode.dev)

## Permissions
All tools pre-approved — no prompts for Bash, Read, Write, Edit, MultiEdit,
WebFetch, WebSearch, Task, Agent, Grep, Glob, LS, MCP tools.

## Agent teams
Agent teams are enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`).
Use parallel subagents for complex tasks via the Task tool.

## Git conventions
- Default branch: main
- Always use `gh pr create` to open PRs
- Commit messages: `type: description` (feat, fix, refactor, docs, chore)

## Docker
- Compose files: `/docker/<service>/docker-compose.yml`
- All containers need `security_opt: [apparmor=unconfined]` in this LXC

## Recommended plugins (install inside Claude Code)

### Superpowers — structured development methodology
Enforces: brainstorm → design → plan → implement (subagents) → TDD → review
```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

### Other useful plugins (from official marketplace)
```
/plugin install code-review@claude-plugins-official
/plugin install commit-commands@claude-plugins-official
/plugin install security-guidance@claude-plugins-official
```
EOF
msg_ok "Workspace ready at /project"

# ─── 12. Git global defaults ──────────────────────────────────────────────────────

msg_info "Configuring Git defaults"
git config --file "$REAL_HOME/.gitconfig" init.defaultBranch main
git config --file "$REAL_HOME/.gitconfig" core.editor nano
git config --file "$REAL_HOME/.gitconfig" pull.rebase false
git config --file "$REAL_HOME/.gitconfig" core.autocrlf false
[[ "$REAL_USER" != "root" ]] && chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.gitconfig" || true
msg_ok "Git defaults configured"

# ─── 13. Shell environment ────────────────────────────────────────────────────────

msg_info "Configuring shell environment"
cat >> "$REAL_HOME/.bashrc" <<'EOF'

# ── Claude Agentic ──────────────────────────────────────────────
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export EDITOR=nano
export PATH="$HOME/.local/bin:$HOME/.claude/bin:$HOME/.cargo/bin:/usr/local/go/bin:$PATH"
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

alias ll='ls -lah --color=auto'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'
alias gs='git status'
alias gl='git log --oneline -20'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'

# Start in /project by default
[[ -d /project ]] && cd /project
EOF
msg_ok "Shell environment configured"

# ─── 14. SSH ──────────────────────────────────────────────────────────────────────

msg_info "Configuring SSH"
sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication yes/" /etc/ssh/sshd_config
log_run systemctl enable --now ssh
msg_ok "SSH configured"

# ─── 15. Update command ───────────────────────────────────────────────────────────

msg_info "Installing 'update' command"
cat > /usr/local/bin/update <<'EOF'
#!/usr/bin/env bash
# Claude Agentic — Update
# Run this command inside the LXC or VM to update all components.

# Refuse to run on the Proxmox host
if [[ -d /etc/pve ]]; then
  echo "This command must be run inside the LXC or VM, not on the Proxmox host." >&2
  exit 1
fi

[[ $EUID -ne 0 ]] && exec sudo "$0" "$@"

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

echo -e "\n ${BOLD}${YW}Claude Agentic — Update${CL}\n"

msg_info "Updating system packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
apt-get autoremove -y -qq
msg_ok "System packages updated"

msg_info "Updating Claude Code"
curl -fsSL https://claude.ai/install.sh | bash \
  || npm update -g @anthropic-ai/claude-code
msg_ok "Claude Code updated ($(claude --version 2>/dev/null || echo 'latest'))"

if command -v code-server &>/dev/null; then
  msg_info "Updating code-server"
  curl -fsSL https://code-server.dev/install.sh | sh
  systemctl restart code-server@root 2>/dev/null || true
  msg_ok "code-server updated"
fi

if command -v code &>/dev/null; then
  msg_info "Updating VS Code Tunnel (CLI)"
  if curl -fL 'https://update.code.visualstudio.com/latest/cli-linux-x64/stable' \
      -o /tmp/vscode-cli.tar.gz 2>/dev/null; then
    mkdir -p /tmp/_vscode_tmp
    tar -xzf /tmp/vscode-cli.tar.gz -C /tmp/_vscode_tmp/ 2>/dev/null || true
    _code_bin=$(find /tmp/_vscode_tmp -name code -type f 2>/dev/null | head -1)
    [[ -n "$_code_bin" ]] && mv "$_code_bin" /usr/local/bin/code && chmod +x /usr/local/bin/code
    rm -rf /tmp/vscode-cli.tar.gz /tmp/_vscode_tmp
  fi
  msg_ok "VS Code Tunnel updated"
fi

echo -e "\n ${CM} ${BOLD}${GN}All updates applied.${CL}\n"
EOF
chmod +x /usr/local/bin/update
msg_ok "Installed 'update' command (/usr/local/bin/update)"

# ─── 16. Scheduled updates (weekly cron) ─────────────────────────────────────────

msg_info "Setting up weekly auto-update"
cat > /etc/cron.weekly/claude-agentic-update <<'CRON'
#!/usr/bin/env bash
apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq && apt-get autoremove -y -qq
curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null || npm update -g @anthropic-ai/claude-code 2>/dev/null || true
curl -fsSL https://code-server.dev/install.sh | sh 2>/dev/null || true
systemctl restart code-server@root 2>/dev/null || true
CRON
chmod +x /etc/cron.weekly/claude-agentic-update

cat > /etc/logrotate.d/claude-agentic <<'EOF'
/var/log/claude-agentic-update.log {
    monthly
    rotate 3
    compress
    missingok
    notifempty
}
EOF
msg_ok "Weekly auto-update scheduled"

# ─── 16. Cleanup ──────────────────────────────────────────────────────────────────

msg_info "Cleaning up"
log_run apt-get autoremove -y
log_run apt-get clean
rm -rf /var/lib/apt/lists/*
msg_ok "Cleaned up"

# ─── 17. MOTD ─────────────────────────────────────────────────────────────────────

msg_info "Writing login banner"
SERVER_IP=$(hostname -I | awk '{print $1}')

IDE_LINES=""
[[ "$IDE_CHOICE" == "codeserver" || "$IDE_CHOICE" == "both" ]] && \
  IDE_LINES="${IDE_LINES}  ║  Code Server:  https://${SERVER_IP}:8443\n  ║  Password:     ${CS_PASSWORD}\n"
[[ "$IDE_CHOICE" == "tunnel" || "$IDE_CHOICE" == "both" ]] && \
  IDE_LINES="${IDE_LINES}  ║  VS Code Tunnel: run 'code tunnel' once to authenticate\n"

printf "
  ╔═══════════════════════════════════════════════════════╗
  ║           Claude Agentic Environment                  ║
  ╠═══════════════════════════════════════════════════════╣
%b  ║                                                       ║
  ║  Start Claude: claude                                 ║
  ║  Workspace:    /project                               ║
  ║  Plugins doc:  cat /project/CLAUDE.md                 ║
  ╚═══════════════════════════════════════════════════════╝
" "$IDE_LINES" > /etc/motd
msg_ok "Login banner configured"

# ─── Done ─────────────────────────────────────────────────────────────────────────

if [[ -n "$FUNCTIONS_FILE_PATH" ]]; then
  motd_ssh
  customize
  cleanup_lxc
else
  echo -e "\n ${CM} ${BOLD}${GN}Installation complete!${CL}\n"
  [[ "$IDE_CHOICE" == "codeserver" || "$IDE_CHOICE" == "both" ]] && \
    echo -e "  ${INFO} Code Server : ${BOLD}https://${SERVER_IP}:8443${CL}  (password: ${CS_PASSWORD})"
  [[ "$IDE_CHOICE" == "tunnel" || "$IDE_CHOICE" == "both" ]] && \
    echo -e "  ${INFO} VS Code Tunnel: run ${BOLD}code tunnel${CL} once to authenticate"
  echo -e "  ${INFO} Workspace   : ${BOLD}/project${CL}"
  echo -e "  ${INFO} Claude Code : run ${BOLD}claude${CL} and follow the login link\n"
  echo -e "  ${YW}Recommended first step in Claude Code:${CL}"
  echo -e "  ${BOLD}/plugin marketplace add obra/superpowers-marketplace${CL}"
  echo -e "  ${BOLD}/plugin install superpowers@superpowers-marketplace${CL}\n"
fi
