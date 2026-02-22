#!/usr/bin/env bash
set -euo pipefail
ACTION=${1:-help}
POLICY=/home/node/.openclaw/bridge/policy.json
CMD_POLICY=/home/node/.openclaw/bridge/command-policy.json

case "$ACTION" in
  run-once)
    exec /opt/op-and-chloe/scripts/guard-bridge-runner.py
    ;;
  policy)
    cat "$POLICY" 2>/dev/null || echo '{}'
    ;;
  command-policy)
    cat "$CMD_POLICY" 2>/dev/null || echo '{}'
    ;;
  *)
    cat <<EOF
Usage:
  $0 run-once
  $0 policy
  $0 command-policy
EOF
    ;;
esac
