#!/usr/bin/env bash
# Worker (Chloe) entrypoint: load Bitwarden session into environment so all processes
# (including agent-invoked shells) see it. Then exec OpenClaw.
set -euo pipefail
BW_ENV="/home/node/.openclaw/secrets/bitwarden.env"
BW_SESSION_FILE="/home/node/.openclaw/secrets/bw-session"
export BITWARDENCLI_APPDATA_DIR="/home/node/.openclaw/bitwarden-cli"
[ -f "$BW_ENV" ] && . "$BW_ENV"
[ -f "$BW_SESSION_FILE" ] && export BW_SESSION=$(cat "$BW_SESSION_FILE")
exec "$@"
