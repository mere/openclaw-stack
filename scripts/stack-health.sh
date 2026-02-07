#!/usr/bin/env bash
set -euo pipefail

INSTANCE=${INSTANCE:-chloe}
GW_CONTAINER=${GW_CONTAINER:-${INSTANCE}-openclaw-gateway}
BROWSER_CONTAINER=${BROWSER_CONTAINER:-${INSTANCE}-browser}

printf "== containers ==\n"
docker ps --format "{{.Names}}\t{{.Status}}\t{{.Image}}" \
  | awk "BEGIN{print \"NAME\\tSTATUS\\tIMAGE\"} /^${INSTANCE}-/{print}"

echo
printf "== gateway port mapping ==\n"
docker port "$GW_CONTAINER" 18789/tcp 2>/dev/null || echo "(no port mapping found)"

echo
printf "== CDP smoke test ==\n"
/opt/openclaw-stack/scripts/cdp-smoke-test.sh

echo
printf "== recent gateway logs (tail) ==\n"
docker logs "$GW_CONTAINER" --tail=20
