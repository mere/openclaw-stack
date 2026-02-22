#!/usr/bin/env bash
# Guard entrypoint: exec OpenClaw. Bitwarden runs in the worker only; no bridge.
set -euo pipefail
exec "$@"
