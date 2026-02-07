#!/usr/bin/env bash
set -euo pipefail

BROWSER_CONTAINER=${BROWSER_CONTAINER:-chloe-browser}
GATEWAY_CONTAINER=${GATEWAY_CONTAINER:-chloe-openclaw-gateway}
CDP_PORT=${CDP_PORT:-9223}

BIP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" "$BROWSER_CONTAINER")
if [ -z "$BIP" ]; then
  echo "Could not determine browser container IP for: $BROWSER_CONTAINER" >&2
  exit 1
fi

URL="http://$BIP:$CDP_PORT/json/version"

printf "Browser container IP: %s\n" "$BIP"
printf "CDP URL: %s\n" "$URL"

# Chromium CDP is picky about Host headers; use IP explicitly.
docker exec "$GATEWAY_CONTAINER" sh -lc "curl -sS --max-time 3 $URL" \
  | python3 - <<PY
import json,sys
j=json.load(sys.stdin)
need=["Browser","Protocol-Version","webSocketDebuggerUrl"]
missing=[k for k in need if k not in j]
if missing:
  raise SystemExit("Missing keys in CDP /json/version: %r"%missing)
print("OK: CDP reachable")
print("Browser:", j.get("Browser"))
print("WS:", j.get("webSocketDebuggerUrl"))
PY
