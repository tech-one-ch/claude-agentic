#!/usr/bin/env bash
# Claude Agentic — Installation check script
# Usage: bash tests/check.sh [--export [file]]

set -uo pipefail

# ─── Colors ────────────────────────────────────────────────────────────────────

GN=$(printf '\033[1;92m')
RD=$(printf '\033[01;31m')
YW=$(printf '\033[33m')
BL=$(printf '\033[36m')
BOLD=$(printf '\033[1m')
DIM=$(printf '\033[2m')
CL=$(printf '\033[m')

LBL_PASS="${GN}✔ PASS${CL}"
LBL_FAIL="${RD}✖ FAIL${CL}"
LBL_WARN="${YW}⚠ WARN${CL}"
LBL_SKIP="${DIM}– SKIP${CL}"

# ─── Export option ─────────────────────────────────────────────────────────────

EXPORT_FILE=""
if [[ "${1:-}" == "--export" ]]; then
  EXPORT_FILE="${2:-check-results-$(date +%Y%m%d-%H%M%S).txt}"
fi

# ─── Result tracking ───────────────────────────────────────────────────────────

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0
declare -a LINES=()

record() {
  local label="$1"
  local status="$2"   # pass | fail | warn | skip
  local detail="$3"
  local lbl
  case "$status" in
    pass) lbl="$LBL_PASS"; PASS_COUNT=$((PASS_COUNT+1)) ;;
    fail) lbl="$LBL_FAIL"; FAIL_COUNT=$((FAIL_COUNT+1)) ;;
    warn) lbl="$LBL_WARN"; WARN_COUNT=$((WARN_COUNT+1)) ;;
    skip) lbl="$LBL_SKIP"; SKIP_COUNT=$((SKIP_COUNT+1)) ;;
  esac
  LINES+=("  ${lbl}  ${BOLD}${label}${CL}  ${DIM}${detail}${CL}")
}

# ─── Helper: check a command version ───────────────────────────────────────────

check_cmd() {
  local label="$1"
  local cmd="$2"
  local version_cmd="${3:-$cmd --version}"
  local output
  if ! command -v "$cmd" &>/dev/null; then
    record "$label" fail "not found"
    return
  fi
  output=$(eval "$version_cmd" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
  record "$label" pass "${output:-OK}"
}

# ─── Helper: check a systemd service ───────────────────────────────────────────

check_service() {
  local label="$1"
  local service="$2"
  local status
  status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
  if [[ "$status" == "active" ]]; then
    record "$label" pass "active"
  else
    record "$label" fail "$status"
  fi
}

# ─── Helper: check a file or directory ─────────────────────────────────────────

check_path() {
  local label="$1"
  local path="$2"
  if [[ -e "$path" ]]; then
    record "$label" pass "$path"
  else
    record "$label" fail "$path not found"
  fi
}

# ─── Environment detection ─────────────────────────────────────────────────────

detect_env() {
  if [[ -f /.dockerenv ]]; then
    echo "Docker container"
    return
  fi
  if grep -qi "microsoft" /proc/version 2>/dev/null; then
    echo "WSL"
    return
  fi
  if command -v systemd-detect-virt &>/dev/null; then
    local virt
    virt=$(systemd-detect-virt 2>/dev/null)
    case "$virt" in
      lxc|lxc-libvirt) echo "LXC container" ;;
      kvm)             echo "VM (KVM/QEMU)" ;;
      vmware)          echo "VM (VMware)" ;;
      xen)             echo "VM (Xen)" ;;
      microsoft)       echo "VM (Hyper-V)" ;;
      none)            echo "Physical machine" ;;
      *)               echo "VM ($virt)" ;;
    esac
    return
  fi
  if grep -q "container=lxc" /proc/1/environ 2>/dev/null; then
    echo "LXC container"
    return
  fi
  echo "Unknown"
}

# ─── Header ────────────────────────────────────────────────────────────────────

ENV_TYPE=$(detect_env)
OS_NAME=$(grep -oP '(?<=^PRETTY_NAME=").*(?=")' /etc/os-release 2>/dev/null || echo "Unknown OS")
HOSTNAME=$(hostname)
DATE=$(date '+%Y-%m-%d %H:%M:%S')
IP=$(hostname -I | tr -s ' \n' '\n' | grep -Eo '([0-9]+\.){3}[0-9]+' | tail -1)

output() {
  echo ""
  echo -e "${BOLD}${BL}  Claude Agentic — Installation Check${CL}"
  echo -e "  ${DIM}${DATE}${CL}"
  echo ""
  echo -e "  ${BOLD}Environment:${CL}  $ENV_TYPE"
  echo -e "  ${BOLD}Hostname:${CL}     $HOSTNAME"
  echo -e "  ${BOLD}OS:${CL}           $OS_NAME"
  echo -e "  ${BOLD}IP:${CL}           ${IP:-N/A}"
  echo ""

  # ── 1. Languages & runtimes ─────────────────────────────────────────────────
  echo -e "  ${BOLD}Languages & runtimes${CL}"
  check_cmd "Node.js"  "node"    "node --version"
  check_cmd "npm"      "npm"     "npm --version"
  check_cmd "Python 3" "python3" "python3 --version"
  check_cmd "Go"       "go"      "go version"
  check_cmd "Rust"     "rustc"   "rustc --version"
  check_cmd "Cargo"    "cargo"   "cargo --version"

  for l in "${LINES[@]}"; do echo -e "$l"; done
  LINES=()
  echo ""

  # ── 2. Dev tools ─────────────────────────────────────────────────────────────
  echo -e "  ${BOLD}Dev tools${CL}"
  check_cmd "git"     "git"     "git --version"
  check_cmd "jq"      "jq"      "jq --version"
  check_cmd "yq"      "yq"      "yq --version"
  check_cmd "ripgrep" "rg"      "rg --version"
  check_cmd "fd"      "fd"      "fd --version"
  check_cmd "fzf"     "fzf"     "fzf --version"
  check_cmd "bat"     "bat"     "bat --version"
  check_cmd "tmux"    "tmux"    "tmux -V"
  check_cmd "gh"      "gh"      "gh --version"

  for l in "${LINES[@]}"; do echo -e "$l"; done
  LINES=()
  echo ""

  # ── 3. Docker ────────────────────────────────────────────────────────────────
  echo -e "  ${BOLD}Docker${CL}"
  check_cmd     "docker"          "docker"  "docker --version"
  check_service "docker service"  "docker"
  if command -v docker &>/dev/null && systemctl is-active docker &>/dev/null; then
    local compose_out
    compose_out=$(docker compose version 2>/dev/null | head -1)
    if [[ -n "$compose_out" ]]; then
      record "docker compose" pass "$compose_out"
    else
      record "docker compose" fail "plugin not found"
    fi
  else
    record "docker compose" skip "docker not running"
  fi

  for l in "${LINES[@]}"; do echo -e "$l"; done
  LINES=()
  echo ""

  # ── 4. Claude Code ───────────────────────────────────────────────────────────
  echo -e "  ${BOLD}Claude Code${CL}"
  check_cmd  "claude"           "claude"  "claude --version"
  check_path "settings.json"   "/root/.claude/settings.json"
  check_path "workspace"       "/project"
  check_path "CLAUDE.md"       "/project/CLAUDE.md"

  for l in "${LINES[@]}"; do echo -e "$l"; done
  LINES=()
  echo ""

  # ── 5. Web IDE ───────────────────────────────────────────────────────────────
  echo -e "  ${BOLD}Web IDE${CL}"
  check_cmd     "code-server"        "code-server"  "code-server --version"
  check_service "code-server@root"   "code-server@root"
  if command -v code &>/dev/null; then
    check_cmd "VS Code Tunnel CLI" "code" "code --version"
  else
    record "VS Code Tunnel CLI" skip "not installed"
  fi

  for l in "${LINES[@]}"; do echo -e "$l"; done
  LINES=()
  echo ""

  # ── 6. System ────────────────────────────────────────────────────────────────
  echo -e "  ${BOLD}System${CL}"
  check_cmd  "update command"  "update"  "which update"
  check_path "install log"     "/var/log/claude-agentic-install.log"

  local disk_use
  disk_use=$(df -h / | awk 'NR==2{print $3 " used / " $2 " total (" $5 " used)"}')
  record "disk /" pass "$disk_use"

  local mem_use
  mem_use=$(free -h | awk '/^Mem:/{print $3 " used / " $2 " total"}')
  record "memory" pass "$mem_use"

  for l in "${LINES[@]}"; do echo -e "$l"; done
  LINES=()
  echo ""

  # ── Summary ──────────────────────────────────────────────────────────────────
  local total=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT + SKIP_COUNT))
  echo -e "  ─────────────────────────────────────────"
  echo -e "  ${BOLD}Results${CL}  ${GN}${PASS_COUNT} passed${CL}  ${RD}${FAIL_COUNT} failed${CL}  ${YW}${WARN_COUNT} warnings${CL}  ${DIM}${SKIP_COUNT} skipped${CL}  (${total} total)"

  if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "  ${GN}${BOLD}All checks passed.${CL}"
  else
    echo -e "  ${RD}${BOLD}${FAIL_COUNT} check(s) failed — review the items above.${CL}"
  fi
  echo ""
}

# ─── Run & optionally export ───────────────────────────────────────────────────

if [[ -n "$EXPORT_FILE" ]]; then
  output | tee "$EXPORT_FILE"
  # Strip ANSI codes from the exported file
  sed -i 's/\x1b\[[0-9;]*m//g' "$EXPORT_FILE"
  echo -e "  ${BL}Results exported to: ${BOLD}${EXPORT_FILE}${CL}"
  echo ""
else
  output
fi
