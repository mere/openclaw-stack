#!/usr/bin/env bash
set -euo pipefail

INSTANCE=${INSTANCE:-op-and-chloe}
BROWSER_CONTAINER=${BROWSER_CONTAINER:-${INSTANCE}-browser}
GATEWAY_CONTAINER=${GATEWAY_CONTAINER:-${INSTANCE}-openclaw-gateway}
CDP_PORT=${CDP_PORT:-9223}

if ! docker ps -a --format '{{.Names}}' | grep -q "^${BROWSER_CONTAINER}$"; then
  echo "Browser container '$BROWSER_CONTAINER' not found."
  echo "Run: sudo ./start.sh  (or setup option 4: Run start browser)" >&2
  exit 1
fi

BIP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" "$BROWSER_CONTAINER" 2>/dev/null || true)
if [ -z "$BIP" ]; then
  echo "Browser container exists but has no network IP (may still be starting)." >&2
  echo "Wait a moment and run healthcheck again." >&2
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
