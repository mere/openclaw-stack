#!/usr/bin/env bash
set -euo pipefail

STACK_DIR=${STACK_DIR:-/opt/op-and-chloe}
ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
STATE_JSON=${STATE_JSON:-/var/lib/openclaw/state/openclaw.json}
CDP_PORT=${CDP_PORT:-9223}
PROFILE_NAME=${PROFILE_NAME:-vps-chromium}

# Use same instance naming as setup.sh and compose
if [ -f "$ENV_FILE" ]; then
  INSTANCE=$(grep -E '^INSTANCE=' "$ENV_FILE" | cut -d= -f2- | tr -d '"' | head -1)
fi
INSTANCE=${INSTANCE:-op-and-chloe}
BROWSER_CONTAINER=${BROWSER_CONTAINER:-${INSTANCE}-browser}

# If the stack pins a static IP, prefer it.
if [ -n "${BROWSER_IPV4:-}" ]; then
  BIP="$BROWSER_IPV4"
else
  BIP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" "$BROWSER_CONTAINER")
fi

if [ -z "$BIP" ]; then
  echo "Could not determine browser container IP for: $BROWSER_CONTAINER" >&2
  exit 1
fi

echo "Using browser IP: $BIP"

STATE_JSON="$STATE_JSON" PROFILE_NAME="$PROFILE_NAME" BIP="$BIP" CDP_PORT="$CDP_PORT" python3 - <<'PY'
import json, os
from pathlib import Path
p = Path(os.environ["STATE_JSON"])
j = json.loads(p.read_text())
j.setdefault("browser", {})
j["browser"]["enabled"] = True
j["browser"].setdefault("profiles", {})
profile = os.environ.get("PROFILE_NAME", "vps-chromium")
bip = os.environ["BIP"]
port = os.environ.get("CDP_PORT", "9223")
j["browser"]["profiles"].setdefault(profile, {})["cdpUrl"] = f"http://{bip}:{port}"
j["browser"]["defaultProfile"] = profile
p.write_text(json.dumps(j, indent=2) + "\n")
print("Updated", p)
PY

chown -R 1000:1000 /var/lib/openclaw/state

cd "$STACK_DIR"
docker compose --env-file "${ENV_FILE}" -f compose.yml restart openclaw-gateway

echo "OK: set cdpUrl to http://$BIP:$CDP_PORT"
