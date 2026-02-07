#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
STACK_DIR=${STACK_DIR:-/opt/openclaw-stack}
BASE=${BASE:-$STACK_DIR/compose.yml}
REPO_OVR=${REPO_OVR:-$STACK_DIR/compose.breakglass.repo.yml}
DOCKER_OVR=${DOCKER_OVR:-$STACK_DIR/compose.breakglass.docker.yml}

MODE=${MODE:-normal}

cd "$STACK_DIR"

echo "[stop] mode=$MODE"

case "$MODE" in
  normal)
    echo "[stop] stopping services (no volume deletion)"
    docker compose --env-file "$ENV_FILE" -f "$BASE" stop
    ;;
  breakglass)
    echo "[stop] returning gateway to normal mode (remove repo/docker.sock mounts)"
    docker compose --env-file "$ENV_FILE" -f "$BASE" up -d --force-recreate openclaw-gateway
    ;;
  *)
    echo "Unknown MODE=$MODE (use normal|breakglass)" >&2
    exit 2
    ;;
esac
