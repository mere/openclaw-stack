#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=${STACK_DIR:-$SCRIPT_DIR}
ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}

# Use same INSTANCE as docker compose (from env file)
if [ -f "$ENV_FILE" ]; then
  export INSTANCE=$(grep -E '^INSTANCE=' "$ENV_FILE" | cut -d= -f2- | tr -d '"' | head -1)
fi
export INSTANCE=${INSTANCE:-op-and-chloe}

bash "$STACK_DIR/scripts/host/stack-health.sh"

echo

echo "== watchdog timer =="
systemctl is-enabled openclaw-cdp-watchdog.timer >/dev/null 2>&1 && systemctl is-active openclaw-cdp-watchdog.timer >/dev/null 2>&1 \
  && echo "openclaw-cdp-watchdog.timer: enabled+active" \
  || echo "openclaw-cdp-watchdog.timer: not enabled/active"
