#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=${STACK_DIR:-$SCRIPT_DIR}
COMPOSE_FILE=${COMPOSE_FILE:-$STACK_DIR/compose.yml}

cd "$STACK_DIR"

if [ -n "${1:-}" ]; then
  echo "[restart] restarting service: $1"
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" restart "$1"
else
  echo "[restart] stopping stack"
  STACK_DIR="$STACK_DIR" ENV_FILE="$ENV_FILE" "$STACK_DIR/stop.sh"

  echo "[restart] starting stack"
  STACK_DIR="$STACK_DIR" ENV_FILE="$ENV_FILE" "$STACK_DIR/start.sh"
fi
