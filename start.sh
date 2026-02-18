#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=${STACK_DIR:-$SCRIPT_DIR}
COMPOSE_FILE=${COMPOSE_FILE:-$STACK_DIR/compose.yml}

cd "$STACK_DIR"

echo "[start] syncing core instructions into workspaces"
"$STACK_DIR/scripts/sync-workspaces.sh"

echo "[start] building guard image (openclaw-guard-tools:local)"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" build openclaw-guard

echo "[start] pulling images"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull browser openclaw-gateway

echo "[start] bringing stack up"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d

echo "[start] container status"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps

echo "[start] warming up browser/CDP"
sleep 10

if tailscale status >/dev/null 2>&1; then
  echo "[start] applying Tailscale serve (Worker, Guard, Webtop)"
  "$STACK_DIR/scripts/apply-tailscale-serve.sh" 2>/dev/null || true
fi
echo "[start] healthcheck"
STACK_DIR="$STACK_DIR" ENV_FILE="$ENV_FILE" "$STACK_DIR/healthcheck.sh"
