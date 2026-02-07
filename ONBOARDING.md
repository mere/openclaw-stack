# Chloe Onboarding Playbook (WIP)

This file is the step-by-step checklist Chloe follows when onboarding a new person onto a Hetzner VPS.

Opinionated assumptions:
- 1 VPS = 1 instance
- Ubuntu 24.04 LTS
- No public exposure; access via Tailscale (phone-friendly) or SSH tunnel

## What the user does (Hetzner)
1) Create a new Hetzner VPS (Ubuntu 24.04).
2) Collect:
   - VPS public IP
   - One-time root password (they should change it after setup)
3) Install Tailscale on their phone (iOS/Android) and sign in.

The user sends Chloe:
- VPS IP
- one-time root password

## What Chloe does (server bootstrap)

### 1) SSH in
```bash
ssh root@<VPS_IP>
```

### 2) Install baseline packages
```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg git
```

### 3) Install Docker + Compose plugin
```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
```

### 4) Create standard directories (bind mounts)
```bash
mkdir -p /opt/openclaw-stack /etc/openclaw
mkdir -p /var/lib/openclaw/state /var/lib/openclaw/workspace /var/lib/openclaw/browser
chown -R 1000:1000 /var/lib/openclaw/state /var/lib/openclaw/workspace /var/lib/openclaw/browser
```

### 5) Configure instance env
Create `/etc/openclaw/stack.env` (never commit secrets):
```bash
INSTANCE=chloe
NOVNC_HOST=127.0.0.1
NOVNC_PORT=6080
GATEWAY_HOST=127.0.0.1
GATEWAY_PORT=18789
OPENCLAW_GATEWAY_TOKEN=<random>
OPENCLAW_STATE_DIR=/var/lib/openclaw/state
OPENCLAW_WORKSPACE_DIR=/var/lib/openclaw/workspace
BROWSER_CONFIG_DIR=/var/lib/openclaw/browser
BROWSER_CDP_URL=http://browser:9222
```

### 6) Start stack
```bash
systemctl daemon-reload
systemctl enable --now openclaw-stack.service
systemctl restart openclaw-stack.service
```

Verify:
```bash
systemctl --no-pager status openclaw-stack.service

docker ps
```

## Tailscale: phone-friendly access

### 1) Install Tailscale on the VPS
```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### 2) Join the tailnet (user approves in their phone/laptop browser)
```bash
tailscale up --hostname chloe-<name>
```

This prints a login URL. Chloe sends it to the user. The user opens it on their phone/laptop browser (not on the VPS) and approves.

Verify:
```bash
tailscale status
tailscale ip -4
```

### 3) Enable Tailscale Serve (required for HTTPS)

When Chloe runs `tailscale serve ...`, Tailscale may respond:

> Serve is not enabled on your tailnet. To enable, visit: https://login.tailscale.com/f/serve?node=...

Chloe sends that URL to the user. The user opens it and enables Serve.

### 4) Configure HTTPS Serve endpoints
```bash
tailscale serve reset

# noVNC
tailscale serve --bg --set-path /novnc http://127.0.0.1:6080

# OpenClaw
tailscale serve --bg --set-path /openclaw http://127.0.0.1:18789

tailscale serve status
```

### 5) User URLs (on phone, with Tailscale enabled)
- `https://<magicdns>/novnc`
- `https://<magicdns>/openclaw`

Example MagicDNS:
- `chloe-throwaway-hel1.tail804ca1.ts.net`

## After setup
- User changes the VPS root password.
- (Recommended) Switch to SSH key auth and disable password auth.
