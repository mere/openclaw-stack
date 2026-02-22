#!/usr/bin/env bash
set -euo pipefail
# View bridge policy (bridge server runs in guard entrypoint; no file-based processing).
ACTION=${1:-help}
# View bridge policy (run from guard container; PATH includes scripts/guard).
POLICY=/home/node/.openclaw/bridge/policy.json
CMD_POLICY=/home/node/.openclaw/bridge/command-policy.json

case "$ACTION" in
  policy)
    cat "$POLICY" 2>/dev/null || echo '{}'
    ;;
  command-policy)
    cat "$CMD_POLICY" 2>/dev/null || echo '{}'
    ;;
  *)
    cat <<EOF
Usage:
  $0 policy
  $0 command-policy
EOF
    ;;
esac
