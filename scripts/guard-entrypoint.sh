#!/usr/bin/env bash
# Load Bitwarden session into environment so the guard process and all children
# (including Op's commands) see the vault as unlocked. Same session file and env
# that setup uses; no wrapper or workaround.
set -euo pipefail
BW_ENV="/home/node/.openclaw/secrets/bitwarden.env"
BW_SESSION_FILE="/home/node/.openclaw/secrets/bw-session"
export BITWARDENCLI_APPDATA_DIR="/home/node/.openclaw/bitwarden-cli"
[ -f "$BW_ENV" ] && . "$BW_ENV"
[ -f "$BW_SESSION_FILE" ] && export BW_SESSION=$(cat "$BW_SESSION_FILE")
exec "$@"
