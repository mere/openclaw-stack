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
rid=sys.argv[1]
timeout=int(sys.argv[2])
p=pathlib.Path('/var/lib/openclaw/bridge/outbox')/f'{rid}.json'
end=time.time()+timeout
while time.time()<end:
    if p.exists():
        try:
            d=json.loads(p.read_text())
        except Exception:
            time.sleep(1)
            continue
        if d.get('status') and d.get('status')!='pending_approval':
            print(json.dumps(d,indent=2))
            sys.exit(0)
    time.sleep(1)
print(json.dumps({'requestId':rid,'status':'timeout','error':'bridge_timeout_waiting_for_final_result'},indent=2))
sys.exit(2)
PY
}

submit_command(){
  local cmd="$1" reason="$2"
  python3 - "$cmd" "$reason" <<'PY'
import json, pathlib, sys, secrets, datetime
rid=secrets.token_hex(4)
o={
  'requestId':rid,
  'requestedBy':'worker',
  'command':sys.argv[1],
  'reason':sys.argv[2],
  'createdAt':datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')
}
(pathlib.Path('/var/lib/openclaw/bridge/inbox')/f'{rid}.json').write_text(json.dumps(o,indent=2)+'\n')
print(rid)
PY
}

parse_flags(){
  REASON=''
  TIMEOUT='120'
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) REASON="${2:-}"; shift 2 ;;
      --timeout) TIMEOUT="${2:-120}"; shift 2 ;;
      *)
        if [[ "$1" =~ ^[0-9]+$ ]] && [ $# -eq 1 ]; then
          TIMEOUT="$1"; shift 1
        else
          echo "unknown flag: $1" >&2
          exit 1
        fi
        ;;
    esac
  done
}

case "$SUB" in
  call)
    TARGET=${1:-}; shift || true
    [ -n "$TARGET" ] || { echo "usage: $0 call '<command>' --reason '<reason>' [--timeout N]" >&2; exit 1; }
    parse_flags "$@"
    [ -n "$REASON" ] || { echo "reason required" >&2; exit 1; }
    RID=$(submit_command "$TARGET" "$REASON")
    wait_result "$RID" "$TIMEOUT"
    ;;
  catalog)
    cat /var/lib/openclaw/bridge/commands.json
    ;;
  *)
    cat <<EOF
Usage:
  $0 call '<command>' --reason '<reason>' [--timeout N]
  $0 catalog

Notes:
  - Direct command model only (no action wrappers).
  - Calls block until outbox contains a final status (ok|error|rejected) or timeout.
EOF
    ;;
esac
