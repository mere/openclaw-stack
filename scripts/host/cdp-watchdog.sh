#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=${STACK_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}
COMPOSE_FILE=${COMPOSE_FILE:-$STACK_DIR/compose.yml}

# 1) If CDP ok -> exit
if bash "$STACK_DIR/scripts/host/cdp-smoke-test.sh" >/dev/null 2>&1; then
  exit 0
fi

echo "[watchdog] CDP smoke test failed; restarting browser then refreshing CDP URL in worker state"

cd "$STACK_DIR"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" restart browser
sleep 5
# Refresh worker state with current browser CDP URL and restart gateway so Chloe's browser tool works
STACK_DIR="$STACK_DIR" ENV_FILE="$ENV_FILE" bash "$STACK_DIR/scripts/host/update-webtop-cdp-url.sh" 2>/dev/null || true
sleep 3

# Re-test
bash "$STACK_DIR/scripts/host/cdp-smoke-test.sh"
