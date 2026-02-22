#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# Run via bash so it works even when scripts/host/setup.sh has no execute bit (e.g. after git clone).
exec bash "$SCRIPT_DIR/scripts/host/setup.sh" "$@"
