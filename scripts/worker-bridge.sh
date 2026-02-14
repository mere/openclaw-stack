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
    REASON=${4:-}
    [ -n "$ACTION" ] || { echo "usage: $0 request <action> '<args-json>' <reason>"; exit 1; }
    [ -n "$REASON" ] || { echo "reason required"; exit 1; }
    python3 - "$ACTION" "$ARGS" "$REASON" <<'PY'
import json, pathlib, sys, uuid, datetime
action=sys.argv[1]
args=json.loads(sys.argv[2])
reason=sys.argv[3]
rid=str(uuid.uuid4())
obj={
  'requestId': rid,
  'requestedBy': 'worker',
  'action': action,
  'args': args,
  'reason': reason,
  'createdAt': datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')
}
out=pathlib.Path('/var/lib/openclaw/bridge/inbox')/f'{rid}.json'
out.write_text(json.dumps(obj, indent=2)+'\n')
print(rid)
PY
    ;;
  request-run)
    COMMAND=${2:-}
    REASON=${3:-}
    [ -n "$COMMAND" ] || { echo "usage: $0 request-run '<command>' '<reason>'"; exit 1; }
    [ -n "$REASON" ] || { echo "reason required"; exit 1; }
    python3 - "$COMMAND" "$REASON" <<'PY'
import json, pathlib, sys, uuid, datetime
command=sys.argv[1]
reason=sys.argv[2]
rid=str(uuid.uuid4())
obj={
  'requestId': rid,
  'requestedBy': 'worker',
  'command': command,
  'reason': reason,
  'createdAt': datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')
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
  $0 request <action> '<args-json>' '<reason>'
  $0 request-run '<command>' '<reason>'
  $0 result <requestId>
EOF
    ;;
esac
