# Chloe Onboarding Playbook (WIP)

This file is the step-by-step checklist Chloe follows when onboarding a new person onto a Hetzner VPS.

Opinionated assumptions:
- 1 VPS = 1 instance
- Ubuntu 24.04 LTS
- No public exposure; access via Tailscale (phone-friendly) or SSH tunnel


## Required: SSH access (for onboarding wizard + channel setup)

Even if you plan to use the phone-only Tailscale HTTPS URLs day-to-day, **initial setup requires an SSH terminal**.

Reason: model OAuth (Codex), Telegram bot tokens, WhatsApp pairing/QR, and other channel setup steps are handled by the **interactive onboarding wizard (TUI)**. Trying to run this from phone-only web terminals (Hetzner web console / iOS) makes it hard or impossible to copy OAuth URLs and tokens.

### Run the wizard (on the VPS host)

SSH to the VPS, then run the wizard inside the gateway container:

```bash
ssh root@<VPS_IP>

docker exec -it chloe-openclaw-gateway ./openclaw.mjs onboard
```

Notes:
- In our current gateway image, the CLI entrypoint is **`./openclaw.mjs`** inside the container (there is no `openclaw` binary on `$PATH`).
- For Codex OAuth, the wizard prints a login URL. Open it on your laptop/phone and then paste the resulting redirect URL back into the wizard.
- The final redirect is usually `http://localhost:1455/auth/callback?...` and may show a "page not found". **That is expected** — copy the URL from the address bar.

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
(removed) BROWSER_CDP_URL=http://browser:9222
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


## Wizard selections (Codex OAuth)

For OpenAI Codex OAuth we used:
- Onboarding mode: **Quick start**
- Config handling: **Use existing values**
- Auth choice: **OpenAI (Codex OAuth)**
- Provider: **OpenAI Codex (ChatGPT OAuth)**



## Browser automation (CDP) using Webtop + socat

We want OpenClaw to automate the **same** logged-in Chromium that you use manually in webtop.

### Why socat?
Chromium CDP in this webtop image tends to bind to localhost (127.0.0.1). To make it reachable from the OpenClaw gateway container, we proxy it:

- Chromium: `127.0.0.1:9222`
- socat: `0.0.0.0:9223 -> 127.0.0.1:9222`

### Important: Host header restriction

### Important: Host header restriction
Chromium rejects CDP requests when the `Host:` header is not `localhost` or an IP. That means `http://browser:9223` may fail.

So we set `cdpUrl` using the **container IP**, e.g. `http://172.18.0.2:9223`.

### Setup (container boot)
We install two init scripts into the webtop config volume (so they persist):

- `/config/custom-cont-init.d/20-start-chromium-cdp`
- `/config/custom-cont-init.d/30-start-socat-cdp-proxy`

They start chromium (with CDP enabled) and socat on container boot.

### Verify
From the gateway container:

```bash
docker exec chloe-openclaw-gateway curl -sS http://<WEBTOP_IP>:9223/json/version
```

### Keep `cdpUrl` up to date
If the webtop container IP changes after restart, run:

```bash
/opt/openclaw-stack/scripts/update-webtop-cdp-url.sh
```


### CDP smoke test

Run this on the VPS host:

```bash
/opt/openclaw-stack/scripts/cdp-smoke-test.sh
```


### Pin the webtop container IP (recommended)

To avoid the webtop container IP changing across recreates, set a static IP via Docker network IPAM. This stack supports:

- `DOCKER_SUBNET` (default `172.31.0.0/24`)
- `BROWSER_IPV4` (default `172.31.0.10`)

Add them to `/etc/openclaw/stack.env`:

```bash
DOCKER_SUBNET=172.31.0.0/24
BROWSER_IPV4=172.31.0.10
```

Then recreate the stack:

```bash
cd /opt/openclaw-stack
docker compose --env-file /etc/openclaw/stack.env -f compose.yml up -d --force-recreate
```

Once pinned, `browser.profiles.webtop.cdpUrl` can stay `http://172.31.0.10:9223` permanently.


### Source of truth for CDP

This stack does **not** rely on a `BROWSER_CDP_URL` env var. The gateway reads `browser.profiles.webtop.cdpUrl` from `/var/lib/openclaw/state/openclaw.json`. With the pinned browser IP, that value can stay stable (e.g. `http://172.31.0.10:9223`).


## Operations: health check + watchdog

### Quick health check

```bash
/opt/openclaw-stack/scripts/stack-health.sh
```

### CDP watchdog (auto-recovery)

A systemd timer runs every ~2 minutes and restarts the browser + gateway if CDP stops responding.

Check status:

```bash
systemctl status openclaw-cdp-watchdog.timer
journalctl -u openclaw-cdp-watchdog.service -n 50 --no-pager
```

Disable:

```bash
systemctl disable --now openclaw-cdp-watchdog.timer
```

## Cleanup (optional)

If you used the webtop Desktop helper files during onboarding (gateway token / OAuth URL launcher), you can remove them:

- `/var/lib/openclaw/browser/Desktop/OPENCLAW_GATEWAY_TOKEN.txt`
- `/var/lib/openclaw/browser/Desktop/CODEX_OAUTH_URL.txt`
- `/var/lib/openclaw/browser/Desktop/OpenAI-Codex-OAuth.desktop`


## Handy commands (mobile-friendly)

These wrappers keep commands short for phone SSH.

Start:
```bash
sudo /opt/openclaw-stack/start.sh
```

Health check:
```bash
sudo /opt/openclaw-stack/healthcheck.sh
```

Stop:
```bash
sudo /opt/openclaw-stack/stop.sh
```

Break-glass start (repo + Docker host control):
```bash
sudo /opt/openclaw-stack/start-breakglass.sh
```

Break-glass stop (return to normal):
```bash
sudo MODE=breakglass /opt/openclaw-stack/stop.sh
```
