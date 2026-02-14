#!/usr/bin/env bash
set -euo pipefail
CMD=${1:-help}
ROOT=/var/lib/openclaw/bridge
INBOX=$ROOT/inbox
OUTBOX=$ROOT/outbox
mkdir -p "$INBOX" "$OUTBOX"

case "$CMD" in
  request)
    ACTION=${2:-}
    ARGS=${3:-"{}"}
    [ -n "$ACTION" ] || { echo "usage: $0 request <action> '<args-json>'"; exit 1; }
    python3 - "$ACTION" "$ARGS" <<'PY'
import json, pathlib, sys, uuid, datetime
action=sys.argv[1]
args=json.loads(sys.argv[2])
rid=str(uuid.uuid4())
obj={
  'requestId': rid,
  'requestedBy': 'worker',
  'action': action,
  'args': args,
  'createdAt': datetime.datetime.utcnow().replace(microsecond=0).isoformat()+'Z'
}
out=pathlib.Path('/var/lib/openclaw/bridge/inbox')/f'{rid}.json'
out.write_text(json.dumps(obj, indent=2)+'\n')
print(rid)
PY
    ;;
  result)
    RID=${2:-}; [ -n "$RID" ] || { echo "usage: $0 result <requestId>"; exit 1; }
    cat "$OUTBOX/$RID.json"
    ;;
  *)
    cat <<EOF
Usage:
  $0 request <action> '<args-json>'
  $0 result <requestId>
EOF
    ;;
esac
