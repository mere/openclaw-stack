#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=${STACK_DIR:-$SCRIPT_DIR}

"$STACK_DIR/scripts/stack-health.sh"

echo

echo "== watchdog timer =="
systemctl is-enabled openclaw-cdp-watchdog.timer >/dev/null 2>&1 && systemctl is-active openclaw-cdp-watchdog.timer >/dev/null 2>&1 \
  && echo "openclaw-cdp-watchdog.timer: enabled+active" \
  || echo "openclaw-cdp-watchdog.timer: not enabled/active"
