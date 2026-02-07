#!/usr/bin/env bash
set -euo pipefail

STACK_DIR=${STACK_DIR:-/opt/openclaw-stack}

"$STACK_DIR/scripts/stack-health.sh"

echo

echo "== watchdog timer =="
systemctl is-enabled openclaw-cdp-watchdog.timer >/dev/null 2>&1 && systemctl is-active openclaw-cdp-watchdog.timer >/dev/null 2>&1 \
  && echo "openclaw-cdp-watchdog.timer: enabled+active" \
  || echo "openclaw-cdp-watchdog.timer: not enabled/active"
