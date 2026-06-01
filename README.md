# Claude Dev — Proxmox LXC & Standalone Installer

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
| **Docker** | latest | + Compose, Watchtower |
| **GitHub CLI** | latest | `gh` — for PR automation |
| **Dev tools** | — | ripgrep, fd, fzf, bat, tmux, htop… |

---

## Option A — Proxmox LXC (recommended)

Run on your **Proxmox host**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/ct/claude-dev.sh)"
```

Default resources: **4 vCPU · 4 GB RAM · 20 GB disk · Ubuntu 24.04 · privileged**

The interactive dialog lets you change all of these (Advanced mode).

### Update an existing LXC

Run the same command from inside the container, or from the Proxmox host:
```bash
pct exec <CTID> -- bash -c "$(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/ct/claude-dev.sh)"
```

---

## Option B — Standalone (any Debian/Ubuntu)

Run on your **existing VM, VPS, or LXC** as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/install/claude-dev-install.sh)"
```

Tested on: **Ubuntu 22.04, Ubuntu 24.04, Debian 12**

### Update standalone installation

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/misc/update.sh)"
```

---

## First use

1. **Set your API key** (once, inside the container/VM):
   ```bash
   export ANTHROPIC_API_KEY='sk-ant-...'
   # Or add it permanently:
   echo "export ANTHROPIC_API_KEY='sk-ant-...'" >> ~/.bashrc
   ```

2. **Open Code Server** in your browser: `https://<IP>:8443`
   - Password is shown in the terminal at the end of installation
   - Also visible at login: `cat /etc/motd`

3. **Start Claude Code** from the Code Server terminal:
   ```bash
   cd /root/projects
   claude
   ```

4. **Authenticate GitHub CLI** (for PR automation):
   ```bash
   gh auth login
   ```

---

## PR automation workflow

Once everything is set up, Claude Code can create PRs automatically:

```bash
cd /root/projects/my-repo
claude "Add a dark mode toggle to the settings page, then open a PR on GitHub"
```

Claude has full access to `Bash`, `Read`, `Write`, `Edit`, `WebFetch`, `gh`, and all standard tools.

---

## Repository structure

```
claude-dev/
├── ct/
│   └── claude-dev.sh          # Proxmox LXC creator (community-scripts style)
├── install/
│   └── claude-dev-install.sh  # App installer (dual mode: Proxmox LXC + standalone)
└── misc/
    └── update.sh              # Standalone updater
```

---

## Credits

- Installer style based on [Proxmox VE Community Scripts](https://community-scripts.github.io/ProxmoxVE/)
- App installation inspired by [serversathome-personal/code](https://github.com/serversathome-personal/code/blob/main/agentic.sh)
