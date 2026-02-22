#!/usr/bin/env bash
# In the guard: run this so bw sees the session from setup step 6 (no interactive unlock).
# Usage: bw-with-session.sh status | bw-with-session.sh list items ...
set -euo pipefail
BW_ENV="/home/node/.openclaw/secrets/bitwarden.env"
BW_SESSION_FILE="/home/node/.openclaw/secrets/bw-session"
BW_DATA_DIR="/home/node/.openclaw/bitwarden-cli"
export BITWARDENCLI_APPDATA_DIR="$BW_DATA_DIR"
[ -f "$BW_ENV" ] && . "$BW_ENV"
[ -f "$BW_SESSION_FILE" ] && export BW_SESSION=$(cat "$BW_SESSION_FILE")
[ -n "${BW_SERVER:-}" ] && bw config server "$BW_SERVER" >/dev/null 2>&1 || true
exec bw "$@"
