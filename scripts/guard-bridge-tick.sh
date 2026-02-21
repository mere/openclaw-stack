#!/usr/bin/env bash
set -euo pipefail
# Host-side tick: process one bridge item inside the running guard container
GUARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep 'openclaw-guard' | head -1 || true)
if [ -n "$GUARD_CONTAINER" ]; then
  docker exec "$GUARD_CONTAINER" /opt/op-and-chloe/scripts/guard-bridge.sh run-once >/dev/null 2>&1 || true
fi
