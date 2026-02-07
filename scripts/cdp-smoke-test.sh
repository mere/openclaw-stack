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
export OUT

python3 - <<PY
import json, os, sys
raw = (os.environ.get("OUT") or "").strip()
if not raw:
    print("ERROR: empty response from CDP endpoint", file=sys.stderr)
    raise SystemExit(1)
try:
    j = json.loads(raw)
except Exception:
    print("ERROR: could not parse JSON from CDP endpoint", file=sys.stderr)
    print("First 200 chars:", raw[:200], file=sys.stderr)
    raise
need = ["Browser", "Protocol-Version", "webSocketDebuggerUrl"]
missing = [k for k in need if k not in j]
if missing:
    raise SystemExit(f"Missing keys in CDP /json/version: {missing}")
print("OK: CDP reachable")
print("Browser:", j.get("Browser"))
print("WS:", j.get("webSocketDebuggerUrl"))
PY
