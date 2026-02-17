#!/usr/bin/env bash
set -euo pipefail
ACTION=${1:-help}
PENDING=/home/node/.openclaw/bridge/pending.json
POLICY=/home/node/.openclaw/bridge/policy.json
CMD_POLICY=/home/node/.openclaw/bridge/command-policy.json

case "$ACTION" in
  run-once)
    exec /opt/op-and-chloe/scripts/guard-bridge-runner.py
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
  decision)
    TEXT=${2:-}
    [ -n "$TEXT" ] || { echo "usage: $0 decision '<guard approve|deny ...>'"; exit 1; }
    python3 - "$TEXT" <<'PY'
import re, subprocess, sys
text=sys.argv[1].strip()
patterns=[
    (r'^guard\s+approve\s+always\s+([a-f0-9]{8})$', ('approve','always')),
    (r'^guard\s+approve\s+([a-f0-9]{8})$', ('approve','once')),
    (r'^guard\s+deny\s+always\s+([a-f0-9]{8})$', ('reject','always')),
    (r'^guard\s+deny\s+([a-f0-9]{8})$', ('reject','once')),
]
for pat,(act,mode) in patterns:
    m=re.match(pat,text,re.I)
    if m:
        rid=m.group(1)
        raise SystemExit(subprocess.call(['/opt/op-and-chloe/scripts/guard-bridge.sh',act,rid,mode]))
print('no_match')
raise SystemExit(2)
PY
    ;;
  clear-pending)
    python3 - <<'PY'
import json, pathlib, datetime
pending_p=pathlib.Path('/home/node/.openclaw/bridge/pending.json')
outbox=pathlib.Path('/var/lib/openclaw/bridge/outbox'); outbox.mkdir(parents=True, exist_ok=True)
def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')
pending=json.loads(pending_p.read_text() if pending_p.exists() else '{}')
for req_id in list(pending.keys()):
    (outbox/f'{req_id}.json').write_text(json.dumps({'requestId':req_id,'status':'rejected','error':'manual_clear_pending','completedAt':now()}, indent=2)+'\n')
pending_p.write_text('{}\n')
print('cleared:'+str(len(pending)))
PY
    ;;
  approve|reject)
    REQ=${2:-}
    MODE=${3:-once}
    [ -n "$REQ" ] || { echo "usage: $0 $ACTION <requestId-or-prefix> [once|always]"; exit 1; }
    python3 - "$ACTION" "$REQ" "$MODE" <<'PY'
import json, pathlib, subprocess, sys, re
action, req_in, mode = sys.argv[1], sys.argv[2], sys.argv[3]
pending_p=pathlib.Path('/home/node/.openclaw/bridge/pending.json')
policy_p=pathlib.Path('/home/node/.openclaw/bridge/policy.json')
cmd_policy_p=pathlib.Path('/home/node/.openclaw/bridge/command-policy.json')
outbox=pathlib.Path('/var/lib/openclaw/bridge/outbox'); outbox.mkdir(parents=True, exist_ok=True)

def now():
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')

pending=json.loads(pending_p.read_text() if pending_p.exists() else '{}')
req_id=req_in
if req_in not in pending:
    # prefix match (8+ chars recommended)
    matches=[k for k in pending.keys() if k.startswith(req_in)]
    if len(matches)==1:
        req_id=matches[0]
    elif len(matches)>1:
        print('ambiguous_prefix:'+','.join(matches[:5])); sys.exit(2)

item=pending.get(req_id)
if not item:
    print('request_not_found'); sys.exit(1)
req=item['request']
matched=item.get('matchedRule','')
matched_ids=item.get('matchedRuleIds')
if not isinstance(matched_ids, list):
    # fallback: try to read from analysis
    an=item.get('analysis')
    if isinstance(an, dict) and isinstance(an.get('matchedRuleIds'), list):
        matched_ids=an.get('matchedRuleIds')

if mode=='always':
    cp=json.loads(cmd_policy_p.read_text() if cmd_policy_p.exists() else '{"rules":[]}')
    ids=set([str(x) for x in matched_ids]) if isinstance(matched_ids, list) else set()

    # If there is no explicit match (no_match), persist an exact-command rule.
    if (not ids) or ('no_match' in ids):
        cmd_text=(req.get('command') or '').strip()
        if not cmd_text:
            print('cannot_set_always_without_command')
            sys.exit(2)
        rid='user-'+req_id
        escaped=re.escape(cmd_text)
        cp.setdefault('rules', []).append({
            'id': rid,
            'pattern': r'^'+escaped+r'$',
            'decision': 'approved' if action=='approve' else 'rejected',
        })
    else:
        for r in cp.get('rules',[]):
            if r.get('id') in ids:
                r['decision']='approved' if action=='approve' else 'rejected'

    cmd_policy_p.write_text(json.dumps(cp, indent=2)+'\n')

if action=='reject':
    (outbox/f'{req_id}.json').write_text(json.dumps({'requestId':req_id,'status':'rejected','error':'manual_reject','completedAt':now()}, indent=2)+'\n')
else:
    if req.get('action'):
        (outbox/f'{req_id}.json').write_text(json.dumps({'requestId':req_id,'status':'error','error':'unsupported_action','completedAt':now()}, indent=2)+'\n')
        pending.pop(req_id, None)
        pending_p.write_text(json.dumps(pending, indent=2)+'\n')
        print('done:'+req_id)
        sys.exit(0)
    cmd=['/opt/op-and-chloe/scripts/guard-exec-command.py', req.get('command','')]
    pr=subprocess.run(cmd, capture_output=True, text=True)
    raw=(pr.stdout or '').strip() or (pr.stderr or '').strip()
    try: res=json.loads(raw) if raw else {'ok': pr.returncode==0}
    except Exception: res={'ok': pr.returncode==0, 'raw': raw}
    status='ok' if pr.returncode==0 else 'error'
    (outbox/f'{req_id}.json').write_text(json.dumps({'requestId':req_id,'status':status,'result':res,'completedAt':now()}, indent=2)+'\n')

pending.pop(req_id, None)
pending_p.write_text(json.dumps(pending, indent=2)+'\n')
print('done:'+req_id)
PY
    ;;
  *)
    cat <<EOF
Usage:
  $0 run-once
  $0 pending
  $0 policy
  $0 command-policy
  $0 clear-pending
  $0 approve <requestId-or-prefix> [once|always]
  $0 reject <requestId-or-prefix> [once|always]
  $0 decision "guard approve <id>|guard deny <id>|... always"
EOF
    ;;
esac
