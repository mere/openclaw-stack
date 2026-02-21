#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=${STACK_DIR:-$SCRIPT_DIR}

cd "$STACK_DIR"

echo "[restart] stopping stack"
STACK_DIR="$STACK_DIR" ENV_FILE="$ENV_FILE" "$STACK_DIR/stop.sh"

echo "[restart] starting stack"
STACK_DIR="$STACK_DIR" ENV_FILE="$ENV_FILE" "$STACK_DIR/start.sh"
