#!/usr/bin/env bash
# Bridge client: request/response over Unix socket. No files.
set -euo pipefail

SUB=${1:-help}; shift || true
SOCKET=/var/lib/openclaw/bridge/bridge.sock

bridge_call(){
  local timeout="${1:-120}"
  python3 - "$timeout" <<'PY'
import json, socket, sys
timeout = int(sys.argv[1])
payload = json.loads(sys.stdin.read())
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(timeout)
try:
    sock.connect('/var/lib/openclaw/bridge/bridge.sock')
    sock.sendall((json.dumps(payload) + '\n').encode('utf-8'))
    sock.shutdown(socket.SHUT_WR)
    buf = b''
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        buf += chunk
        if b'\n' in buf:
            break
    line = buf.decode('utf-8', errors='replace').split('\n')[0]
    if line:
        print(line)
except (FileNotFoundError, ConnectionRefusedError, OSError) as e:
    print(json.dumps({'requestId': payload.get('requestId',''), 'status': 'error', 'error': 'bridge_unavailable', 'detail': str(e)}, indent=2))
    sys.exit(2)
finally:
    sock.close()
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
    python3 - "$TARGET" "$REASON" "$TIMEOUT" <<'PYCALL'
import json, secrets, socket, sys
cmd, reason, timeout = sys.argv[1], sys.argv[2], int(sys.argv[3])
payload = {"requestId": secrets.token_hex(4), "requestedBy": "worker", "command": cmd, "reason": reason}
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(timeout)
try:
    sock.connect("/var/lib/openclaw/bridge/bridge.sock")
    sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
    sock.shutdown(socket.SHUT_WR)
    buf = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        buf += chunk
        if b"\n" in buf:
            break
    line = buf.decode("utf-8", errors="replace").split("\n")[0]
    if line:
        print(line)
except (FileNotFoundError, ConnectionRefusedError, OSError) as e:
    print(json.dumps({"requestId": payload.get("requestId",""), "status": "error", "error": "bridge_unavailable", "detail": str(e)}, indent=2))
    sys.exit(2)
finally:
    sock.close()
PYCALL
    ;;
  catalog)
    echo '{"requestId":"catalog","requestedBy":"worker","action":"catalog","reason":"catalog"}' | bridge_call 10 | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
if d.get("status") == "ok" and "result" in d:
    print(json.dumps(d["result"], indent=2))
else:
    print(json.dumps(d, indent=2))
'
    ;;
  *)
    cat <<EOF
Usage:
  $0 call '<command>' --reason '<reason>' [--timeout N]
  $0 catalog

Notes:
  - Request/response over Unix socket; no files.
  - Call blocks until guard returns result or timeout.
EOF
    ;;
esac
