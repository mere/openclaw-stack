#!/usr/bin/env bash
set -euo pipefail
ACTION=${1:-}
ARGS_JSON=${2:-{}}

# Placeholder email adapter (guard-only). Intended to be backed by Himalaya + Bitwarden.
# For now, validates CLI availability and returns structured errors/success.

if ! command -v himalaya >/dev/null 2>&1; then
  echo '{"ok":false,"error":"himalaya_not_installed","hint":"Install himalaya on guard and configure account before using bridge email actions."}'
  exit 2
fi

case "$ACTION" in
  email.list|email.read|email.draft|email.send)
    echo '{"ok":false,"error":"not_implemented_yet","hint":"Bridge wired. Himalaya backend mapping pending."}'
    exit 3
    ;;
  *)
    echo '{"ok":false,"error":"unsupported_action"}'
    exit 1
    ;;
esac
