#!/usr/bin/env bash
set -euo pipefail

INSTANCE=${INSTANCE:-chloe}
GW_CONTAINER=${GW_CONTAINER:-${INSTANCE}-openclaw-gateway}

printf "== containers ==\n"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | (head -n1; grep -E "^${INSTANCE}-" || true)

printf "\n== gateway ws port (container listening) ==\n"
docker exec "$GW_CONTAINER" sh -lc "ss -ltnp | grep -E \":18789\\b\" || true"

printf "\n== CDP smoke test ==\n"
/opt/openclaw-stack/scripts/cdp-smoke-test.sh
