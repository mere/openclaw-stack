#!/usr/bin/env bash
set -euo pipefail
# Host-side tick: process one bridge item inside guard container
if docker ps --format '{{.Names}}' | grep -q '^chloe-openclaw-guard$'; then
  docker exec chloe-openclaw-guard /opt/op-and-chloe/scripts/guard-bridge.sh run-once >/dev/null 2>&1 || true
fi
