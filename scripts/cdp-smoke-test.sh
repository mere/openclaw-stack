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

echo "Browser container IP: $BIP"
echo "CDP URL: $URL"

OUT=$(docker exec "$GATEWAY_CONTAINER" sh -lc "curl -sS --max-time 3 $URL" || true)
if [ -z "$OUT" ]; then
  echo "ERROR: empty response from CDP endpoint" >&2
  docker exec "$GATEWAY_CONTAINER" sh -lc "curl -v --max-time 3 $URL" || true
  exit 1
fi

echo "$OUT" | python3 - <<PY
import json,sys
raw=sys.stdin.read()
j=json.loads(raw)
need=["Browser","Protocol-Version","webSocketDebuggerUrl"]
missing=[k for k in need if k not in j]
if missing:
  raise SystemExit("Missing keys in CDP /json/version: %r"%missing)
print("OK: CDP reachable")
print("Browser:", j.get("Browser"))
print("WS:", j.get("webSocketDebuggerUrl"))
PY
