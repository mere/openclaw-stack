#!/usr/bin/env bash
set -euo pipefail
CMD=${1:-help}
ROOT=/var/lib/openclaw/bridge
INBOX=$ROOT/inbox
OUTBOX=$ROOT/outbox
mkdir -p "$INBOX" "$OUTBOX"

wait_result() {
  local rid="$1"
  local timeout="${2:-120}"
  python3 - "$rid" "$timeout" <<'PY'
import json, pathlib, sys, time
rid=sys.argv[1]; timeout=int(sys.argv[2])
out=pathlib.Path('/var/lib/openclaw/bridge/outbox')/f'{rid}.json'
end=time.time()+timeout
while time.time() < end:
    if out.exists():
        try:
            data=json.loads(out.read_text())
        except Exception:
            time.sleep(1); continue
        status=data.get('status')
        if status and status != 'pending_approval':
            print(json.dumps(data, indent=2))
            sys.exit(0)
    time.sleep(1)
print(json.dumps({"requestId": rid, "status":"timeout", "error":"bridge_timeout_waiting_for_final_result"}, indent=2))
sys.exit(2)
PY
}

submit_action() {
  local action="$1" args="$2" reason="$3"
  python3 - "$action" "$args" "$reason" <<'PY'
import json, pathlib, sys, uuid, datetime
action=sys.argv[1]; args=json.loads(sys.argv[2]); reason=sys.argv[3]
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
}

submit_command() {
  local command="$1" reason="$2"
  python3 - "$command" "$reason" <<'PY'
import json, pathlib, sys, uuid, datetime
command=sys.argv[1]; reason=sys.argv[2]
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
}

case "$CMD" in
  request)
    ACTION=${2:-}; ARGS=${3:-"{}"}; REASON=${4:-}
    [ -n "$ACTION" ] || { echo "usage: $0 request <action> '<args-json>' <reason>"; exit 1; }
    [ -n "$REASON" ] || { echo "reason required"; exit 1; }
    submit_action "$ACTION" "$ARGS" "$REASON"
    ;;
  request-run)
    COMMAND=${2:-}; REASON=${3:-}
    [ -n "$COMMAND" ] || { echo "usage: $0 request-run '<command>' '<reason>'"; exit 1; }
    [ -n "$REASON" ] || { echo "reason required"; exit 1; }
    submit_command "$COMMAND" "$REASON"
    ;;
  call)
    ACTION=${2:-}; ARGS=${3:-"{}"}; REASON=${4:-}; TIMEOUT=${5:-120}
    [ -n "$ACTION" ] || { echo "usage: $0 call <action> '<args-json>' <reason> [timeoutSec]"; exit 1; }
    [ -n "$REASON" ] || { echo "reason required"; exit 1; }
    RID=$(submit_action "$ACTION" "$ARGS" "$REASON")
    wait_result "$RID" "$TIMEOUT"
    ;;
  call-run)
    COMMAND=${2:-}; REASON=${3:-}; TIMEOUT=${4:-120}
    [ -n "$COMMAND" ] || { echo "usage: $0 call-run '<command>' '<reason>' [timeoutSec]"; exit 1; }
    [ -n "$REASON" ] || { echo "reason required"; exit 1; }
    RID=$(submit_command "$COMMAND" "$REASON")
    wait_result "$RID" "$TIMEOUT"
    ;;
  result)
    RID=${2:-}; [ -n "$RID" ] || { echo "usage: $0 result <requestId>"; exit 1; }
    cat "$OUTBOX/$RID.json"
    ;;
  catalog)
    cat /var/lib/openclaw/bridge/commands.json
    ;;
  *)
    cat <<EOF
Usage:
  $0 request <action> '<args-json>' '<reason>'
  $0 request-run '<command>' '<reason>'
  $0 call <action> '<args-json>' '<reason>' [timeoutSec]
  $0 call-run '<command>' '<reason>' [timeoutSec]
  $0 result <requestId>
  $0 catalog
EOF
    ;;
esac
