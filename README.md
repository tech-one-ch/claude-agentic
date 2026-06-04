# Claude Agentic — Proxmox LXC & Standalone Installer

Automated installer for a full **Claude Code** development environment.

- **Option A** — Create a fresh LXC on Proxmox (one-liner)
- **Option B** — Install on any existing Debian/Ubuntu system, VM, or VPS

---

## What gets installed

| Component | Version | Notes |
|---|---|---|
| **Claude Code** | latest | All permissions pre-approved |
| **code-server** | latest | VS Code in browser, port 8443 |
| **Node.js** | 22 LTS | via NodeSource |
| **Python** | 3.x | + pip, pipx, uv |
| **Go** | latest | |
| **Rust** | latest | via rustup |
| **Docker** | latest | + Compose plugin |
| **GitHub CLI** | latest | `gh` — for PR automation |
| **Dev tools** | — | ripgrep, fd, fzf, bat, tmux, htop… |

---

## Option A — Proxmox LXC (recommended)

Run on your **Proxmox host**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/ct/claude-agentic.sh)"
```

Default resources: **4 vCPU · 4 GB RAM · 20 GB disk · Ubuntu 24.04 · unprivileged**

The interactive dialog lets you change all of these (Advanced mode).

### Update an existing LXC

**From inside the LXC** (recommended — just type):
```bash
update
```

**Via curl from inside the LXC:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/misc/update.sh)"
```

**From the Proxmox host:**
```bash
pct exec <CTID> -- update
```

---

## Option B — Standalone (any Debian/Ubuntu)

Run on your **existing VM, VPS, or LXC** as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/install/claude-agentic-install.sh)"
```

Tested on: **Ubuntu 22.04, Ubuntu 24.04, Debian 12**

### Update standalone installation

**Type directly (if already installed):**
```bash
update
```

**Via curl:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/misc/update.sh)"
```

---

## First use

1. **Open Code Server** in your browser: `https://<IP>:8443`
   - Password is shown in the terminal at the end of installation
   - Also visible at login: `cat /etc/motd`

2. **Activate VS Code Tunnel** (first time only, inside the container):
   ```bash
   code tunnel
   ```
   Follow the link to authenticate with your GitHub or Microsoft account. After that, the tunnel is accessible at [vscode.dev](https://vscode.dev) or via the VS Code desktop app (Remote Tunnels).

3. **Start Claude Code** from the terminal:
   ```bash
   cd /projects
   claude
   ```
   At first launch, Claude shows a login link — open it in your browser to authenticate with your Anthropic account (no API key needed).

4. **Authenticate GitHub CLI** (for PR automation):
   ```bash
   gh auth login
   ```

---

## PR automation workflow

Once everything is set up, Claude Code can create PRs automatically:

```bash
cd /projects/my-repo
claude "Add a dark mode toggle to the settings page, then open a PR on GitHub"
```

Claude has full access to `Bash`, `Read`, `Write`, `Edit`, `WebFetch`, `gh`, and all standard tools.

---

## Repository structure

```
claude-agentic/
├── ct/
│   └── claude-agentic.sh          # Proxmox LXC creator (community-scripts style)
├── install/
│   └── claude-agentic-install.sh  # App installer (dual mode: Proxmox LXC + standalone)
├── misc/
│   └── update.sh              # Standalone updater (curl-able)
├── checks/                   # Check script — usage, options, Supabase integration
│   ├── check.sh
│   ├── CHECK.md
│   └── TESTING.md
```

---

## Credits

- Installer style based on [Proxmox VE Community Scripts](https://community-scripts.github.io/ProxmoxVE/)
- App installation inspired by [serversathome-personal/code](https://github.com/serversathome-personal/code/blob/main/agentic.sh)
