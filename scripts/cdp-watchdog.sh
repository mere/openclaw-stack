#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
STACK_DIR=${STACK_DIR:-/opt/openclaw-stack}
COMPOSE_FILE=${COMPOSE_FILE:-$STACK_DIR/compose.yml}

# 1) If CDP ok -> exit
if $STACK_DIR/scripts/cdp-smoke-test.sh >/dev/null 2>&1; then
  exit 0
fi

echo "[watchdog] CDP smoke test failed; restarting browser+gateway"

cd "$STACK_DIR"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" restart browser
sleep 5
# Refresh chromium/socat in case webtop init scripts are slow

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" restart openclaw-gateway
sleep 3

# Re-test
$STACK_DIR/scripts/cdp-smoke-test.sh
