# OpenClaw Hetzner VPS (Opinionated)

This is a **work-in-progress** local repo on a throwaway Hetzner VPS.

## Goals

A repeatable, SSH-only OpenClaw deployment on Hetzner with:

- Docker Compose + systemd
- A visible browser desktop (noVNC) for manual logins
- CDP reachable **internally** by service name (e.g. `http://browser:9222`)
- A simple smoke test: open `https://bbc.co.uk` and summarize headlines

## Opinionated defaults

- **1 VPS = 1 instance**
- No public OpenClaw API exposure
- noVNC bound to **127.0.0.1** on the VPS (access via SSH tunnel)
- Instance configuration lives in `/etc/openclaw/stack.env`
- Persistent data lives in `/var/lib/openclaw/...`

## Prerequisites

- Ubuntu 24.04 LTS recommended
- SSH access to the VPS (root or sudo user)

## Step-by-step setup (from a fresh VPS)

### 1) SSH into the VPS

```bash
ssh root@<VPS_IP>
```

If you use a non-standard port:

```bash
ssh -p <PORT> root@<VPS_IP>
```

### 2) Verify OS

```bash
cat /etc/os-release
uname -a
```

### 3) Install Docker + Compose plugin

This uses Docker’s official apt repo.

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg git

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

docker --version
docker compose version
```

### 4) Create standard directories

```bash
mkdir -p /opt/openclaw-stack /etc/openclaw /var/lib/openclaw
mkdir -p /var/lib/openclaw/state /var/lib/openclaw/workspace /var/lib/openclaw/browser
```

### 5) Initialize the local repo

```bash
cd /opt/openclaw-stack
git init
```

(Optional but recommended) Set git identity for local commits:

```bash
git config user.name "Chloe"
git config user.email "chloe@localhost"
```

### 6) Configure the instance env file

Copy the example and edit as needed:

```bash
cp -f /opt/openclaw-stack/config/env.example /etc/openclaw/stack.env
nano /etc/openclaw/stack.env
```

### 7) Install the systemd unit

```bash
cp -f /opt/openclaw-stack/systemd/openclaw-stack.service /etc/systemd/system/openclaw-stack.service
systemctl daemon-reload
systemctl enable --now openclaw-stack.service
```

### 8) Verify everything is running

```bash
systemctl --no-pager status openclaw-stack.service

docker ps

docker compose -f /opt/openclaw-stack/compose.yml ps

journalctl -u openclaw-stack.service -n 100 --no-pager
```

## Browser desktop access (noVNC via SSH tunnel)

The browser desktop is exposed on the VPS at `127.0.0.1:6080`.

From your laptop:

```bash
ssh -L 6080:127.0.0.1:6080 root@<VPS_IP>
```

Then open:

- `http://localhost:6080`

## Troubleshooting

### Service won’t start

```bash
journalctl -u openclaw-stack.service -n 200 --no-pager
```

### Containers not running

```bash
docker ps -a

docker compose -f /opt/openclaw-stack/compose.yml logs --tail=200
```


## Phone access via Tailscale HTTPS (recommended)

Many mobile browsers (especially iOS) require a secure origin (HTTPS) for noVNC and the OpenClaw Control UI.

Use Tailscale + Tailscale Serve to expose HTTPS endpoints inside your tailnet (not publicly on the internet):

1) Install + connect Tailscale (VPS):

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --hostname chloe-<name>
```

2) If Tailscale says Serve is not enabled, open the provided admin URL and enable it.

3) Configure Serve (VPS):

```bash
tailscale serve reset
tailscale serve --bg --set-path /novnc http://127.0.0.1:6080
tailscale serve --bg --set-path /openclaw http://127.0.0.1:18789
tailscale serve status
```

4) On your phone (with Tailscale on):
- `https://<magicdns>/novnc`
- `https://<magicdns>/openclaw`
