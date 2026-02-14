#!/usr/bin/env python3
import json, pathlib, subprocess, re, datetime

BRIDGE_ROOT = pathlib.Path('/var/lib/openclaw/bridge')
INBOX = BRIDGE_ROOT / 'inbox'
OUTBOX = BRIDGE_ROOT / 'outbox'
AUDIT = BRIDGE_ROOT / 'audit' / 'bridge-audit.jsonl'
POLICY_PATH = pathlib.Path('/var/lib/openclaw/guard-state/bridge/policy.json')
CMD_POLICY_PATH = pathlib.Path('/var/lib/openclaw/guard-state/bridge/command-policy.json')
PENDING_PATH = pathlib.Path('/var/lib/openclaw/guard-state/bridge/pending.json')

DEFAULT_POLICY = {
    'email.list': 'approved',
    'email.read': 'approved',
    'email.draft': 'ask',
    'email.send': 'ask',
    'poems.read': 'approved',
    'poems.write': 'rejected',
    'poems.delete': 'ask'
}
DEFAULT_CMD_POLICY = {
    'rules': [
        {'id':'himalaya-list','pattern':r'^himalaya\s+envelope\s+list\b','decision':'approved'},
        {'id':'himalaya-read','pattern':r'^himalaya\s+message\s+read\b','decision':'approved'},
        {'id':'himalaya-send','pattern':r'^himalaya\s+message\s+send\b','decision':'ask'},
        {'id':'git-readonly','pattern':r'^git\s+(status|log|diff)\b','decision':'approved'},
        {'id':'git-push','pattern':r'^git\s+push\b','decision':'ask'},
        {'id':'dangerous','pattern':r'(rm\s+-rf|mkfs|docker\s+system\s+prune)','decision':'rejected'},
    ]
}

for p in [INBOX, OUTBOX, AUDIT.parent, POLICY_PATH.parent]:
    p.mkdir(parents=True, exist_ok=True)

if not POLICY_PATH.exists():
    POLICY_PATH.write_text(json.dumps(DEFAULT_POLICY, indent=2) + '\n')
else:
    cur = json.loads(POLICY_PATH.read_text() or '{}')
    changed = False
    for k, v in DEFAULT_POLICY.items():
        if k not in cur:
            cur[k] = v
            changed = True
    if changed:
        POLICY_PATH.write_text(json.dumps(cur, indent=2) + '\n')

if not CMD_POLICY_PATH.exists():
    CMD_POLICY_PATH.write_text(json.dumps(DEFAULT_CMD_POLICY, indent=2) + '\n')
if not PENDING_PATH.exists():
    PENDING_PATH.write_text('{}\n')

subprocess.run(['/root/openclaw-stack/scripts/guard-bridge-catalog.py'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')

def audit(event):
    with AUDIT.open('a') as f:
        f.write(json.dumps(event, ensure_ascii=False) + '\n')

def load_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except Exception:
        return fallback

def write_out(request_id, payload):
    (OUTBOX / f'{request_id}.json').write_text(json.dumps(payload, indent=2) + '\n')

def wake_guard_for_ask(req, matched=None):
    reason = req.get('reason','(no reason provided)')
    msg = f"Guard approval needed: requestId={req.get('requestId')} action={req.get('action','command.run')} command={req.get('command','')} reason={reason} matchedRule={matched or 'n/a'}"
    subprocess.run([
        'docker','exec','chloe-openclaw-guard','./openclaw.mjs','system','event','--mode','now','--text',msg
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def execute_action(action, args):
    if action.startswith('poems.'):
        cmd = ['/root/openclaw-stack/scripts/guard-poems.sh', action]
    else:
        cmd = ['/root/openclaw-stack/scripts/guard-email.sh', action, json.dumps(args)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    raw = (proc.stdout or '').strip() or (proc.stderr or '').strip()
    try:
        parsed = json.loads(raw) if raw else {'ok': proc.returncode == 0}
    except Exception:
        parsed = {'ok': proc.returncode == 0, 'raw': raw}
    return proc.returncode, parsed

def execute_command(command):
    proc = subprocess.run(['/root/openclaw-stack/scripts/guard-exec-command.py', command], capture_output=True, text=True)
    raw = (proc.stdout or '').strip() or (proc.stderr or '').strip()
    try:
        parsed = json.loads(raw) if raw else {'ok': proc.returncode == 0}
    except Exception:
        parsed = {'ok': proc.returncode == 0, 'raw': raw}
    return proc.returncode, parsed

def decision_for_command(command):
    cfg = load_json(CMD_POLICY_PATH, DEFAULT_CMD_POLICY)
    for rule in cfg.get('rules',[]):
        try:
            if re.search(rule.get('pattern','^$'), command):
                return rule.get('decision','rejected'), rule.get('id','unknown')
        except re.error:
            continue
    return 'rejected', 'no_match'

def process_one(path):
    req = load_json(path, None)
    if not isinstance(req, dict):
        return False
    rid = req.get('requestId')
    who = req.get('requestedBy', 'unknown')
    reason = req.get('reason','')

    if not rid or not reason:
        payload = {'requestId': rid or 'unknown', 'status': 'rejected', 'error': 'invalid_request_missing_id_or_reason', 'completedAt': now_iso()}
        if rid:
            write_out(rid, payload)
        audit({'ts': now_iso(), 'event':'rejected','reason':'invalid_request', 'request': req})
        return True

    action = req.get('action')
    if action:
        args = req.get('args', {})
        if not isinstance(args, dict):
            write_out(rid, {'requestId':rid,'status':'rejected','error':'invalid_args','completedAt':now_iso()})
            return True
        policy = load_json(POLICY_PATH, DEFAULT_POLICY)
        decision = policy.get(action, 'rejected')
        matched='action:'+action
    else:
        command = (req.get('command') or '').strip()
        if not command:
            write_out(rid, {'requestId':rid,'status':'rejected','error':'missing_command_or_action','completedAt':now_iso()})
            return True
        decision, matched = decision_for_command(command)

    if decision == 'rejected':
        write_out(rid, {'requestId':rid,'status':'rejected','error':'policy_rejected','matchedRule':matched,'completedAt':now_iso()})
        audit({'ts':now_iso(),'event':'rejected','requestId':rid,'requestedBy':who,'matchedRule':matched,'reason':reason})
        return True

    if decision == 'ask':
        pending = load_json(PENDING_PATH, {})
        pending[rid] = {'request': req, 'createdAt': now_iso(), 'state': 'pending_approval', 'matchedRule': matched}
        PENDING_PATH.write_text(json.dumps(pending, indent=2) + '\n')
        write_out(rid, {'requestId':rid,'status':'pending_approval','matchedRule':matched,'message':'Awaiting guard approval','completedAt':now_iso()})
        audit({'ts':now_iso(),'event':'pending_approval','requestId':rid,'requestedBy':who,'matchedRule':matched,'reason':reason})
        wake_guard_for_ask(req, matched)
        return True

    if action:
        rc, result = execute_action(action, req.get('args',{}))
    else:
        rc, result = execute_command(req.get('command',''))
    status = 'ok' if rc == 0 else 'error'
    payload = {'requestId':rid,'status':status,'matchedRule':matched,'result':result,'completedAt':now_iso()}
    write_out(rid, payload)
    audit({'ts':now_iso(),'event':status,'requestId':rid,'requestedBy':who,'matchedRule':matched,'reason':reason})
    return True

def main():
    files = sorted(INBOX.glob('*.json'), key=lambda p: p.stat().st_mtime)
    if not files:
        print('no_requests'); return
    f = files[0]
    try:
        ok = process_one(f)
    finally:
        try:
            f.unlink(missing_ok=True)
        except Exception:
            pass
    print('processed' if ok else 'ignored')

if __name__=='__main__':
    main()
