#!/usr/bin/env bash
set -euo pipefail

STACK_DIR=${STACK_DIR:-/opt/openclaw-stack}
STATE_JSON=${STATE_JSON:-/var/lib/openclaw/state/openclaw.json}
BROWSER_CONTAINER=${BROWSER_CONTAINER:-chloe-browser}
CDP_PORT=${CDP_PORT:-9223}
PROFILE_NAME=${PROFILE_NAME:-webtop}

BIP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" "$BROWSER_CONTAINER")
if [ -z "$BIP" ]; then
  echo "Could not determine browser container IP for: $BROWSER_CONTAINER" >&2
  exit 1
fi

echo "Detected browser IP: $BIP"

python3 - <<PY
import json
from pathlib import Path
p=Path("$STATE_JSON")
j=json.loads(p.read_text())
j.setdefault("browser",{})
j["browser"]["enabled"]=True
j["browser"].setdefault("profiles",{})
j["browser"]["profiles"].setdefault("$PROFILE_NAME",{})["cdpUrl"]=f"http://{\"$BIP\"}:$CDP_PORT"
j["browser"]["defaultProfile"]="$PROFILE_NAME"
p.write_text(json.dumps(j,indent=2)+"\n")
print("Updated", p)
PY

chown -R 1000:1000 /var/lib/openclaw/state

cd "$STACK_DIR"
docker compose --env-file /etc/openclaw/stack.env -f compose.yml restart openclaw-gateway

echo "OK: set cdpUrl to http://$BIP:$CDP_PORT"
