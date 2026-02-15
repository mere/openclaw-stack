#!/usr/bin/env bash
set -euo pipefail
ACTION=${1:-help}
PENDING=/home/node/.openclaw/bridge/pending.json
POLICY=/home/node/.openclaw/bridge/policy.json
CMD_POLICY=/home/node/.openclaw/bridge/command-policy.json

case "$ACTION" in
  run-once)
    exec /opt/openclaw-stack/scripts/guard-bridge-runner.py
    ;;
  pending)
    cat "$PENDING" 2>/dev/null || echo '{}'
    ;;
  policy)
    cat "$POLICY" 2>/dev/null || echo '{}'
    ;;
  command-policy)
    cat "$CMD_POLICY" 2>/dev/null || echo '{}'
    ;;
  approve|reject)
    REQ=${2:-}
    MODE=${3:-once}
    [ -n "$REQ" ] || { echo "usage: $0 $ACTION <requestId> [once|always]"; exit 1; }
    python3 - "$ACTION" "$REQ" "$MODE" <<'PY'
import json, pathlib, subprocess, sys, re
action, req_id, mode = sys.argv[1], sys.argv[2], sys.argv[3]
pending_p=pathlib.Path('/home/node/.openclaw/bridge/pending.json')
policy_p=pathlib.Path('/home/node/.openclaw/bridge/policy.json')
cmd_policy_p=pathlib.Path('/home/node/.openclaw/bridge/command-policy.json')
outbox=pathlib.Path('/var/lib/openclaw/bridge/outbox'); outbox.mkdir(parents=True, exist_ok=True)

def now():
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')

pending=json.loads(pending_p.read_text() if pending_p.exists() else '{}')
item=pending.get(req_id)
if not item:
    print('request_not_found'); sys.exit(1)
req=item['request']
matched=item.get('matchedRule','')

# persist policy change for always actions
if mode=='always':
    if matched.startswith('action:'):
        act=matched.split(':',1)[1]
        pol=json.loads(policy_p.read_text() if policy_p.exists() else '{}')
        pol[act]='approved' if action=='approve' else 'rejected'
        policy_p.write_text(json.dumps(pol, indent=2)+'\n')
    else:
        cp=json.loads(cmd_policy_p.read_text() if cmd_policy_p.exists() else '{"rules":[]}')
        for r in cp.get('rules',[]):
            if r.get('id')==matched:
                r['decision']='approved' if action=='approve' else 'rejected'
        cmd_policy_p.write_text(json.dumps(cp, indent=2)+'\n')

if action=='reject':
    (outbox/f'{req_id}.json').write_text(json.dumps({'requestId':req_id,'status':'rejected','error':'manual_reject','completedAt':now()}, indent=2)+'\n')
else:
    if req.get('action'):
        if str(req.get('action','')).startswith('poems.'):
            cmd=['/opt/openclaw-stack/scripts/guard-poems.sh', req['action']]
        else:
            cmd=['/opt/openclaw-stack/scripts/guard-email.sh', req['action'], json.dumps(req.get('args',{}))]
    else:
        cmd=['/opt/openclaw-stack/scripts/guard-exec-command.py', req.get('command','')]
    pr=subprocess.run(cmd, capture_output=True, text=True)
    raw=(pr.stdout or '').strip() or (pr.stderr or '').strip()
    try: res=json.loads(raw) if raw else {'ok': pr.returncode==0}
    except Exception: res={'ok': pr.returncode==0, 'raw': raw}
    status='ok' if pr.returncode==0 else 'error'
    (outbox/f'{req_id}.json').write_text(json.dumps({'requestId':req_id,'status':status,'result':res,'completedAt':now()}, indent=2)+'\n')

pending.pop(req_id, None)
pending_p.write_text(json.dumps(pending, indent=2)+'\n')
print('done')
PY
    ;;
  *)
    cat <<EOF
Usage:
  $0 run-once
  $0 pending
  $0 policy
  $0 command-policy
  $0 approve <requestId> [once|always]
  $0 reject <requestId> [once|always]
EOF
    ;;
esac
