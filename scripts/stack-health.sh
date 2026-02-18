#!/usr/bin/env bash
set -euo pipefail

INSTANCE=${INSTANCE:-op-and-chloe}
GW_CONTAINER=${GW_CONTAINER:-${INSTANCE}-openclaw-gateway}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=${STACK_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}

printf "== containers ==\n"
docker ps --format "{{.Names}}\t{{.Status}}\t{{.Image}}" \
  | awk "BEGIN{print \"NAME\\tSTATUS\\tIMAGE\"} /^${INSTANCE}-/{print}"

echo
printf "== gateway port mapping ==\n"
docker port "$GW_CONTAINER" 18789/tcp 2>/dev/null || echo "(no port mapping found)"

echo
printf "== CDP smoke test ==\n"
"$STACK_DIR"/scripts/cdp-smoke-test.sh

echo
printf "== network/security checks ==\n"
if tailscale status >/dev/null 2>&1; then
  echo "✅ Tailscale - Running"
else
  echo "⚠️  Tailscale - Not running"
fi

echo
printf "== recent gateway logs (tail) ==\n"
docker logs "$GW_CONTAINER" --tail=20
