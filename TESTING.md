# Testing & Verification Guide

## Quick check (recommended)

Run the check script inside the LXC or VM — checks all components at once and shows a summary.

### From `main` (stable)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/tests/check.sh)
```

### From `dev` (testing)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/dev/tests/check.sh)
```

### With export to file

```bash
# Auto-named file
bash <(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/tests/check.sh) --export

# Specific file
bash <(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/tests/check.sh) --export /tmp/results.txt
```

### If the repo is cloned locally

```bash
bash tests/check.sh
bash tests/check.sh --export
bash tests/check.sh --export /tmp/results.txt
```

---

## Manual checks

Run these commands inside the LXC or VM after installation to verify everything works.

---

## 1. System

```bash
# OS and kernel
uname -a
cat /etc/os-release | grep -E "^(NAME|VERSION)="

# Disk space (should have several GB free)
df -h /

# Memory
free -h

# Install log (check for errors)
grep -E "^\[ERROR\]|^E:|^error:|Failed to|404 Not Found" /var/log/claude-agentic-install.log
```

---

## 2. Languages & runtimes

```bash
node --version          # should be v22.x
npm --version
python3 --version       # should be 3.x
go version              # should be go1.x
rustc --version
cargo --version
```

---

## 3. Dev tools

```bash
git --version
jq --version
yq --version
rg --version            # ripgrep
fd --version
fzf --version
bat --version
tmux -V
```

---

## 4. Docker

```bash
# Docker running
systemctl is-active docker

# Docker usable
docker run --rm hello-world

# Compose plugin
docker compose version
```

---

## 5. GitHub CLI

```bash
gh --version

# Auth status (requires login first)
gh auth status
```

---

## 6. Claude Code

```bash
# Binary exists and is on PATH
which claude
claude --version

# Settings file present
cat /root/.claude/settings.json

# Permissions configured (should list all allowed tools)
jq '.permissions.allow' /root/.claude/settings.json

# Start Claude (will prompt for login on first run)
claude --version
```

---

## 7. code-server

```bash
# Service running
systemctl is-active code-server@root

# Port listening
ss -tlnp | grep 8443

# Password
grep password /root/.config/code-server/config.yaml

# Or check MOTD
cat /etc/motd
```

Browser: `https://<IP>:8443`

---

## 8. Update command

```bash
# Command exists and is executable
which update
update --help 2>/dev/null || update
```

---

## 9. Workspace

```bash
# Default workspace exists
ls /project

# CLAUDE.md present
cat /project/CLAUDE.md

# Git defaults
git config --global --list
```

---

## 10. Shell environment

```bash
# PATH includes Rust, Go, Claude
echo $PATH | tr ':' '\n'

# Aliases available
type gs gl dc dps ll
```

---

## Quick one-liner: check all versions

```bash
for cmd in node npm python3 go rustc git docker gh claude code-server jq yq rg fd fzf bat tmux; do
  printf "%-15s" "$cmd:"
  $cmd --version 2>/dev/null | head -1 || echo "NOT FOUND"
done
```

---

## Checking the install log for errors

```bash
# Full log
cat /var/log/claude-agentic-install.log

# Errors only
grep -i "error\|fail\|404\|fatal\|E:" /var/log/claude-agentic-install.log

# Last 50 lines
tail -50 /var/log/claude-agentic-install.log
```
