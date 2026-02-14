#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
STACK_DIR=${STACK_DIR:-/opt/openclaw-stack}
COMPOSE_FILE=${COMPOSE_FILE:-$STACK_DIR/compose.yml}

cd "$STACK_DIR"

echo "[stop] stopping services (no volume deletion)"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" stop
