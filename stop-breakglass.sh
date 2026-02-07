#!/usr/bin/env bash
set -euo pipefail

STACK_DIR=${STACK_DIR:-/opt/openclaw-stack}

# Recreate the gateway in normal mode (no repo mount, no docker.sock)
"$STACK_DIR/start.sh"

echo "Breakglass is OFF (gateway recreated in normal mode)."
