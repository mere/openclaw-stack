#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Run as root: sudo ./scripts/bootstrap-vps.sh" >&2
  exit 1
fi

STACK_DIR=${STACK_DIR:-/opt/openclaw-stack}
ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}

echo "[bootstrap] preflight"
if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script currently supports Debian/Ubuntu hosts." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg git openssl

if ! command -v docker >/dev/null 2>&1; then
  echo "[bootstrap] installing Docker + Compose"
  install -m 0755 -d /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

mkdir -p /etc/openclaw
mkdir -p /var/lib/openclaw/{state,workspace,browser,guard-state,guard-workspace}
chown -R 1000:1000 /var/lib/openclaw/state /var/lib/openclaw/workspace /var/lib/openclaw/browser /var/lib/openclaw/guard-state /var/lib/openclaw/guard-workspace

if [ ! -f "$ENV_FILE" ]; then
  cp "$STACK_DIR/config/env.example" "$ENV_FILE"
fi

# generate tokens if placeholders
if grep -q '^OPENCLAW_GATEWAY_TOKEN=change-me-worker' "$ENV_FILE"; then
  sed -i "s#^OPENCLAW_GATEWAY_TOKEN=.*#OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)#" "$ENV_FILE"
fi
if grep -q '^OPENCLAW_GUARD_GATEWAY_TOKEN=change-me-guard' "$ENV_FILE"; then
  sed -i "s#^OPENCLAW_GUARD_GATEWAY_TOKEN=.*#OPENCLAW_GUARD_GATEWAY_TOKEN=$(openssl rand -hex 24)#" "$ENV_FILE"
fi

# install/update systemd units from repo
install -m 0644 "$STACK_DIR/systemd/openclaw-stack.service" /etc/systemd/system/openclaw-stack.service
install -m 0644 "$STACK_DIR/systemd/openclaw-cdp-watchdog.service" /etc/systemd/system/openclaw-cdp-watchdog.service
install -m 0644 "$STACK_DIR/systemd/openclaw-cdp-watchdog.timer" /etc/systemd/system/openclaw-cdp-watchdog.timer
systemctl daemon-reload
systemctl enable --now openclaw-cdp-watchdog.timer

# optional Bitwarden bootstrap for guard
read -r -p "Configure Bitwarden for guard now? [y/N]: " BW_ANSWER
if [[ "$BW_ANSWER" =~ ^[Yy]$ ]]; then
  mkdir -p /var/lib/openclaw/guard-state/secrets
  chmod 700 /var/lib/openclaw/guard-state/secrets

  read -r -p "BW server URL [https://vault.bitwarden.eu]: " BW_SERVER
  BW_SERVER=${BW_SERVER:-https://vault.bitwarden.eu}
  read -r -p "BW client id: " BW_CLIENTID
  read -r -p "BW client secret: " BW_CLIENTSECRET
  read -r -p "BW email: " BW_EMAIL
  read -r -s -p "BW master password: " BW_PASSWORD
  echo

  cat > /var/lib/openclaw/guard-state/secrets/bitwarden.env <<EOF
BW_SERVER=$BW_SERVER
BW_CLIENTID=$BW_CLIENTID
BW_CLIENTSECRET=$BW_CLIENTSECRET
BW_PASSWORD=$BW_PASSWORD
BW_EMAIL=$BW_EMAIL
EOF
  chown 1000:1000 /var/lib/openclaw/guard-state/secrets /var/lib/openclaw/guard-state/secrets/bitwarden.env
  chmod 600 /var/lib/openclaw/guard-state/secrets/bitwarden.env
  echo "[bootstrap] wrote /var/lib/openclaw/guard-state/secrets/bitwarden.env"
fi

# optional tailscale
read -r -p "Install Tailscale now? [y/N]: " TS_ANSWER
if [[ "$TS_ANSWER" =~ ^[Yy]$ ]]; then
  curl -fsSL https://tailscale.com/install.sh | sh
  echo "Run this next to join tailnet (interactive):"
  echo "  tailscale up --hostname openclaw-$(hostname)"
fi

echo
echo "[bootstrap] done. Next steps:"
echo "1) Review env:   sudo nano $ENV_FILE"
echo "2) Start stack:  sudo $STACK_DIR/start.sh"
echo "3) Guard setup:  docker exec -it chloe-openclaw-guard ./openclaw.mjs setup"
echo "4) Worker setup: docker exec -it chloe-openclaw-gateway ./openclaw.mjs setup"
echo "5) Run health:   sudo $STACK_DIR/healthcheck.sh"
