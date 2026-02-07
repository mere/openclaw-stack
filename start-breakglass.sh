#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
STACK_DIR=${STACK_DIR:-/opt/openclaw-stack}
BASE=${BASE:-$STACK_DIR/compose.yml}
REPO_OVR=${REPO_OVR:-$STACK_DIR/compose.breakglass.repo.yml}
DOCKER_OVR=${DOCKER_OVR:-$STACK_DIR/compose.breakglass.docker.yml}

cd "$STACK_DIR"

echo "[breakglass] enabling breakglass mode"

echo "[breakglass] starting gateway with repo mount"
docker compose --env-file "$ENV_FILE" -f "$BASE" -f "$REPO_OVR" up -d --force-recreate openclaw-gateway

if [ "${BREAKGLASS_DOCKER_SOCK:-1}" = "1" ]; then
  echo "[breakglass] DANGER: enabling docker.sock mount"
  docker compose --env-file "$ENV_FILE" -f "$BASE" -f "$REPO_OVR" -f "$DOCKER_OVR" up -d --force-recreate openclaw-gateway
fi

echo "[breakglass] healthcheck"
"$STACK_DIR/healthcheck.sh"

cat <<MSG

Breakglass is ON.
- Repo mount enabled: /opt/openclaw-stack -> /opt/openclaw-stack (inside gateway)
- docker.sock mount: ${BREAKGLASS_DOCKER_SOCK:-1} (set BREAKGLASS_DOCKER_SOCK=1 to enable; high risk)

To return to normal:
  $STACK_DIR/start.sh
MSG
