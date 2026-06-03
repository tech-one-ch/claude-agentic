#!/usr/bin/env bash
# Claude Agentic — Installation check script
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh) [options]
# Docs:  https://github.com/tech-one-ch/claude-agentic/blob/main/checks/CHECK.md

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

# ─── Flag parsing ──────────────────────────────────────────────────────────────
# Priority: CLI flags > env vars > interactive prompt

EXPORT_FILE=""
USE_SUPABASE=0
CLI_SUPABASE_URL=""
CLI_SUPABASE_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --export)
      shift
      if [[ $# -gt 0 && "${1:-}" != --* ]]; then
        EXPORT_FILE="$1"; shift
      else
        EXPORT_FILE="check-results-$(date +%Y%m%d-%H%M%S).txt"
      fi
      ;;
    --supabase)
      USE_SUPABASE=1; shift
      ;;
    --supabase-url)
      USE_SUPABASE=1; shift
      CLI_SUPABASE_URL="${1:-}"; shift
      ;;
    --supabase-key)
      USE_SUPABASE=1; shift
      CLI_SUPABASE_KEY="${1:-}"; shift
      ;;
    *) shift ;;
  esac
done

# ─── Result tracking ───────────────────────────────────────────────────────────

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0
declare -a LINES=()
declare -a JSON_CHECKS=()

record() {
  local label="$1" status="$2" detail="$3"
  local lbl
  case "$status" in
    pass) lbl="$LBL_PASS"; PASS_COUNT=$((PASS_COUNT+1)) ;;
    fail) lbl="$LBL_FAIL"; FAIL_COUNT=$((FAIL_COUNT+1)) ;;
    warn) lbl="$LBL_WARN"; WARN_COUNT=$((WARN_COUNT+1)) ;;
    skip) lbl="$LBL_SKIP"; SKIP_COUNT=$((SKIP_COUNT+1)) ;;
  esac
  LINES+=("  ${lbl}  ${BOLD}${label}${CL}  ${DIM}${detail}${CL}")
  local el="${label//\"/\\\"}"; local ed="${detail//\"/\\\"}"
  JSON_CHECKS+=("{\"label\":\"${el}\",\"status\":\"${status}\",\"detail\":\"${ed}\"}")
}

flush() {
  for l in "${LINES[@]:-}"; do [[ -n "$l" ]] && echo -e "$l"; done
  LINES=()
}

# ─── Check helpers ─────────────────────────────────────────────────────────────

check_cmd() {
  local label="$1" cmd="$2" version_cmd="${3:-$cmd --version}"
  if ! command -v "$cmd" &>/dev/null; then
    record "$label" fail "not found"; return
  fi
  local out; out=$(eval "$version_cmd" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
  record "$label" pass "${out:-OK}"
}

check_service() {
  local label="$1" service="$2"
  local status; status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
  [[ "$status" == "active" ]] && record "$label" pass "active" \
                               || record "$label" fail "$status"
}

check_path() {
  local label="$1" path="$2"
  [[ -e "$path" ]] && record "$label" pass "$path" \
                   || record "$label" fail "$path not found"
}

# ─── Environment detection ─────────────────────────────────────────────────────

detect_env() {
  if [[ -f /.dockerenv ]]; then echo "Docker container"; return; fi
  if grep -qi "microsoft" /proc/version 2>/dev/null; then echo "WSL"; return; fi
  if command -v systemd-detect-virt &>/dev/null; then
    local v; v=$(systemd-detect-virt 2>/dev/null)
    case "$v" in
      lxc|lxc-libvirt) echo "LXC container" ;;
      kvm)             echo "VM (KVM/QEMU)" ;;
      vmware)          echo "VM (VMware)" ;;
      xen)             echo "VM (Xen)" ;;
      microsoft)       echo "VM (Hyper-V)" ;;
      none)            echo "Physical machine" ;;
      *)               echo "VM ($v)" ;;
    esac
    return
  fi
  grep -q "container=lxc" /proc/1/environ 2>/dev/null && echo "LXC container" || echo "Unknown"
}

# ─── Supabase ──────────────────────────────────────────────────────────────────

send_to_supabase() {
  # Priority: CLI flag > env var > interactive prompt
  local supa_url="${CLI_SUPABASE_URL:-${SUPABASE_URL:-}}"
  local supa_key="${CLI_SUPABASE_KEY:-${SUPABASE_KEY:-}}"

  echo ""
  echo -e "  ${BOLD}${BL}Supabase${CL}"

  if [[ -n "$supa_url" ]]; then
    echo -e "  URL: ${DIM}${supa_url}${CL}"
  else
    echo -ne "  Project URL (e.g. https://abc123.supabase.co, without /rest/v1): "
    read -r supa_url
  fi

  if [[ -n "$supa_key" ]]; then
    echo -e "  Key: ${DIM}[provided]${CL}"
  else
    echo -ne "  Publishable key (or legacy anon key): "
    read -rsp "" supa_key
    echo ""
  fi

  # Sanitize URL: strip whitespace, trailing slash, and /rest/v1 suffix if pasted from docs
  supa_url="${supa_url%% *}"
  supa_url="${supa_url%%/rest/v1*}"
  supa_url="${supa_url%/}"

  # Build JSON
  local details
  if [[ ${#JSON_CHECKS[@]} -gt 0 ]]; then
    details=$(printf '%s,' "${JSON_CHECKS[@]}")
    details="[${details%,}]"
  else
    details="[]"
  fi

  local payload
  payload=$(printf \
    '{"hostname":"%s","env_type":"%s","os_name":"%s","ip":"%s","pass_count":%d,"fail_count":%d,"warn_count":%d,"skip_count":%d,"details":%s}' \
    "$HOSTNAME_VAL" "$ENV_TYPE" "$OS_NAME" "${IP:-}" \
    "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT" "$SKIP_COUNT" \
    "$details")

  local response http_code
  response=$(curl -s -o /tmp/_supa_resp.txt -w "%{http_code}" \
    -X POST "${supa_url}/rest/v1/claude_agentic_checks" \
    -H "apikey: ${supa_key}" \
    -H "Authorization: Bearer ${supa_key}" \
    -H "Content-Type: application/json" \
    -H "Content-Profile: public" \
    -H "Prefer: return=minimal" \
    -d "$payload" 2>/dev/null)
  http_code="$response"
  local body; body=$(cat /tmp/_supa_resp.txt 2>/dev/null); rm -f /tmp/_supa_resp.txt

  local project_ref="${supa_url#https://}"; project_ref="${project_ref%.supabase.co}"

  if [[ "$http_code" == "201" ]]; then
    echo -e "  ${GN}✔${CL} Sent successfully"
    echo -e "  ${DIM}View: https://supabase.com/dashboard/project/${project_ref}/editor${CL}"

  elif echo "$body" | grep -q "42P01\|does not exist"; then
    echo -e "  ${YW}⚠${CL} Table not found. Create it once in your Supabase SQL editor:"
    echo -e "  ${DIM}https://supabase.com/dashboard/project/${project_ref}/sql/new${CL}"
    echo ""
    echo -e "${DIM}"
    cat << 'SQL'
  CREATE TABLE IF NOT EXISTS claude_agentic_checks (
    id          uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at  timestamptz DEFAULT now(),
    hostname    text,
    env_type    text,
    os_name     text,
    ip          text,
    pass_count  int,
    fail_count  int,
    warn_count  int,
    skip_count  int,
    details     jsonb
  );

  ALTER TABLE claude_agentic_checks ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "anon insert only" ON claude_agentic_checks
    FOR INSERT TO anon WITH CHECK (true);
SQL
    echo -e "${CL}"
    echo -e "  Then re-run: ${BOLD}bash checks/check.sh --supabase${CL}"

  else
    echo -e "  ${RD}✖${CL} Error (HTTP ${http_code}): ${body}"
  fi
}

# ─── Main output ───────────────────────────────────────────────────────────────

ENV_TYPE=$(detect_env)
OS_NAME=$(grep -oP '(?<=^PRETTY_NAME=").*(?=")' /etc/os-release 2>/dev/null || echo "Unknown OS")
HOSTNAME_VAL=$(hostname)
IP=$(hostname -I | tr -s ' \n' '\n' | grep -Eo '([0-9]+\.){3}[0-9]+' | tail -1)
DATE=$(date '+%Y-%m-%d %H:%M:%S')

run_checks() {
  echo ""
  echo -e "${BOLD}${BL}  Claude Agentic — Installation Check${CL}"
  echo -e "  ${DIM}${DATE}${CL}"
  echo ""
  echo -e "  ${BOLD}Environment:${CL}  $ENV_TYPE"
  echo -e "  ${BOLD}Hostname:${CL}     $HOSTNAME_VAL"
  echo -e "  ${BOLD}OS:${CL}           $OS_NAME"
  echo -e "  ${BOLD}IP:${CL}           ${IP:-N/A}"
  echo ""

  # 1. Languages
  echo -e "  ${BOLD}Languages & runtimes${CL}"
  check_cmd "Node.js"  "node"    "node --version"
  check_cmd "npm"      "npm"     "npm --version"
  check_cmd "Python 3" "python3" "python3 --version"
  check_cmd "Go"       "go"      "go version"
  check_cmd "Rust"     "rustc"   "rustc --version"
  check_cmd "Cargo"    "cargo"   "cargo --version"
  flush; echo ""

  # 2. Dev tools
  echo -e "  ${BOLD}Dev tools${CL}"
  check_cmd "git"     "git"  "git --version"
  check_cmd "jq"      "jq"   "jq --version"
  check_cmd "yq"      "yq"   "yq --version"
  check_cmd "ripgrep" "rg"   "rg --version"
  check_cmd "fd"      "fd"   "fd --version"
  check_cmd "fzf"     "fzf"  "fzf --version"
  check_cmd "bat"     "bat"  "bat --version"
  check_cmd "tmux"    "tmux" "tmux -V"
  check_cmd "gh"      "gh"   "gh --version"
  flush; echo ""

  # 3. Docker
  echo -e "  ${BOLD}Docker${CL}"
  check_cmd "docker" "docker" "docker --version"
  check_service "docker service" "docker"
  if command -v docker &>/dev/null && systemctl is-active docker &>/dev/null; then
    local co; co=$(docker compose version 2>/dev/null | head -1)
    [[ -n "$co" ]] && record "docker compose" pass "$co" \
                   || record "docker compose" fail "plugin not found"
  else
    record "docker compose" skip "docker not running"
  fi
  flush; echo ""

  # 4. Claude Code
  echo -e "  ${BOLD}Claude Code${CL}"
  check_cmd  "claude"         "claude" "claude --version"
  check_path "settings.json" "/root/.claude/settings.json"
  check_path "workspace"     "/project"
  check_path "CLAUDE.md"     "/project/CLAUDE.md"
  flush; echo ""

  # 5. Web IDE
  echo -e "  ${BOLD}Web IDE${CL}"
  check_cmd     "code-server"       "code-server" "code-server --version"
  check_service "code-server@root"  "code-server@root"
  if command -v code &>/dev/null; then
    check_cmd "VS Code Tunnel CLI" "code" "code --version"
  else
    record "VS Code Tunnel CLI" skip "not installed"
  fi
  flush; echo ""

  # 6. System
  echo -e "  ${BOLD}System${CL}"
  check_cmd  "update command" "update" "which update"
  check_path "install log"   "/var/log/claude-agentic-install.log"
  local disk; disk=$(df -h / | awk 'NR==2{print $3 " used / " $2 " total (" $5 " used)"}')
  record "disk /"  pass "$disk"
  local mem; mem=$(free -h | awk '/^Mem:/{print $3 " used / " $2 " total"}')
  record "memory" pass "$mem"
  flush; echo ""

  # Summary
  local total=$((PASS_COUNT+FAIL_COUNT+WARN_COUNT+SKIP_COUNT))
  echo -e "  ─────────────────────────────────────────────────────"
  echo -e "  ${BOLD}Results${CL}  ${GN}${PASS_COUNT} passed${CL}  ${RD}${FAIL_COUNT} failed${CL}  ${YW}${WARN_COUNT} warnings${CL}  ${DIM}${SKIP_COUNT} skipped${CL}  (${total} total)"
  if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "  ${GN}${BOLD}All checks passed.${CL}"
  else
    echo -e "  ${RD}${BOLD}${FAIL_COUNT} check(s) failed — review the items above.${CL}"
  fi
  echo ""

  [[ $USE_SUPABASE -eq 1 ]] && send_to_supabase
}

# ─── Run & export ──────────────────────────────────────────────────────────────

if [[ -n "$EXPORT_FILE" ]]; then
  run_checks | tee "$EXPORT_FILE"
  sed -i 's/\x1b\[[0-9;]*m//g' "$EXPORT_FILE"
  echo -e "  ${BL}Exported to: ${BOLD}${EXPORT_FILE}${CL}\n"
else
  run_checks
fi
