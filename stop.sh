#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
STACK_DIR=${STACK_DIR:-/opt/openclaw-stack}
COMPOSE_FILE=${COMPOSE_FILE:-$STACK_DIR/compose.yml}

cd "$STACK_DIR"

echo "[stop] stopping services (no volume deletion)"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" stop

echo
# If break-glass was enabled, tell the user how to return to normal.
# (Stop always stops everything; start.sh returns to normal stack definition.)
GW=$(grep -E "^INSTANCE=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
GW=${GW:-chloe}
GW_CONTAINER="${GW}-openclaw-gateway"
if docker inspect "$GW_CONTAINER" >/dev/null 2>&1; then
  if docker inspect -f "{{range .Mounts}}{{println .Source \"->\" .Destination}}{{end}}" "$GW_CONTAINER" \
    | grep -q "/var/run/docker.sock"; then
    echo "[stop] note: break-glass docker.sock mount was in use."
    echo "[stop] next time you want to return to normal mode, run:"
    echo "       sudo $STACK_DIR/start.sh"
  fi
fi
