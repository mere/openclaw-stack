#!/usr/bin/env bash
set -euo pipefail
HOST=${1:-}
PORT=${2:-6080}
if [ -z "$HOST" ]; then
  echo "Usage: $0 <user@host> [local_port]" >&2
  exit 1
fi

echo "Run this on your laptop:" >&2
echo "ssh -L ${PORT}:127.0.0.1:6080 ${HOST}" 
