#!/usr/bin/env bash
set -euo pipefail

# Guard-side: refresh bridge catalog from current scripts/policies.
# Source of truth is scripts + policy files on guard.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/guard-bridge-catalog.py"
echo "Guard tool catalog refreshed: /var/lib/openclaw/bridge/commands.json"
