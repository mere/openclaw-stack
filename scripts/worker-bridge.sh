#!/usr/bin/env bash
set -euo pipefail
SUB=${1:-help}; shift || true
ROOT=/var/lib/openclaw/bridge
INBOX=$ROOT/inbox
OUTBOX=$ROOT/outbox
mkdir -p "$INBOX" "$OUTBOX"

wait_result(){
  local rid="$1" timeout="${2:-120}"
  python3 - "$rid" "$timeout" <<'PY'
import json, pathlib, sys, time
rid=sys.argv[1]; timeout=int(sys.argv[2]); p=pathlib.Path('/var/lib/openclaw/bridge/outbox')/f'{rid}.json'
end=time.time()+timeout
while time.time()<end:
    if p.exists():
        try:d=json.loads(p.read_text())
        except Exception: time.sleep(1); continue
        if d.get('status') and d.get('status')!='pending_approval':
            print(json.dumps(d,indent=2)); sys.exit(0)
    time.sleep(1)
print(json.dumps({'requestId':rid,'status':'timeout','error':'bridge_timeout_waiting_for_final_result'},indent=2)); sys.exit(2)
PY
}

submit_action(){
  local action="$1" args="$2" reason="$3"
  python3 - "$action" "$args" "$reason" <<'PY'
import json, pathlib, sys, uuid, datetime
rid=str(uuid.uuid4())
o={'requestId':rid,'requestedBy':'worker','action':sys.argv[1],'args':json.loads(sys.argv[2]),'reason':sys.argv[3],'createdAt':datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')}
(pathlib.Path('/var/lib/openclaw/bridge/inbox')/f'{rid}.json').write_text(json.dumps(o,indent=2)+'\n')
print(rid)
PY
}

submit_command(){
  local cmd="$1" reason="$2"
  python3 - "$cmd" "$reason" <<'PY'
import json, pathlib, sys, uuid, datetime
rid=str(uuid.uuid4())
o={'requestId':rid,'requestedBy':'worker','command':sys.argv[1],'reason':sys.argv[2],'createdAt':datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')}
(pathlib.Path('/var/lib/openclaw/bridge/inbox')/f'{rid}.json').write_text(json.dumps(o,indent=2)+'\n')
print(rid)
PY
}

parse_flags(){
  local args='{}' reason='' timeout='120'
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      --args) args="${2:-{}}"; shift 2 ;;
      --timeout) timeout="${2:-120}"; shift 2 ;;
      *) echo "unknown flag: $1"; exit 1 ;;
    esac
  done
  printf '%s\n%s\n%s\n' "$args" "$reason" "$timeout"
}

# if TARGET has spaces -> command; else action
submit_target(){
  local target="$1" args="$2" reason="$3"
  if [[ "$target" == *" "* ]]; then submit_command "$target" "$reason"; else submit_action "$target" "$args" "$reason"; fi
}

case "$SUB" in
  request|call)
    TARGET=${1:-}; shift || true
    [ -n "$TARGET" ] || { echo "usage: $0 $SUB '<action-or-command>' --reason '<reason>' [--args '<json>'] [--timeout N]"; exit 1; }
    mapfile -t F < <(parse_flags "$@")
    ARGS="${F[0]}"; REASON="${F[1]}"; TIMEOUT="${F[2]}"
    [ -n "$REASON" ] || { echo "reason required"; exit 1; }
    RID=$(submit_target "$TARGET" "$ARGS" "$REASON")
    if [ "$SUB" = "call" ]; then wait_result "$RID" "$TIMEOUT"; else echo "$RID"; fi
    ;;
  result)
    RID=${1:-}; [ -n "$RID" ] || { echo "usage: $0 result <requestId>"; exit 1; }
    cat "$OUTBOX/$RID.json"
    ;;
  catalog)
    cat /var/lib/openclaw/bridge/commands.json
    ;;
  *)
    cat <<EOF
Usage:
  $0 request '<action-or-command>' --reason '<reason>' [--args '<json>']
  $0 call '<action-or-command>' --reason '<reason>' [--args '<json>'] [--timeout N]
  $0 result <requestId>
  $0 catalog

Examples:
  $0 call 'poems.read' --reason 'User asked for poem' --timeout 30
  $0 call 'git status' --reason 'User asked for repo status' --timeout 30
EOF
    ;;
esac
