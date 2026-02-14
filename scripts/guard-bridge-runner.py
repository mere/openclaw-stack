#!/usr/bin/env python3
import json, os, time, pathlib, subprocess, sys

BRIDGE_ROOT = pathlib.Path('/var/lib/openclaw/bridge')
INBOX = BRIDGE_ROOT / 'inbox'
OUTBOX = BRIDGE_ROOT / 'outbox'
AUDIT = BRIDGE_ROOT / 'audit' / 'bridge-audit.jsonl'
POLICY_PATH = pathlib.Path('/var/lib/openclaw/guard-state/bridge/policy.json')
PENDING_PATH = pathlib.Path('/var/lib/openclaw/guard-state/bridge/pending.json')

DEFAULT_POLICY = {
    'email.list': 'approved',
    'email.read': 'approved',
    'email.draft': 'ask',
    'email.send': 'ask'
}

for p in [INBOX, OUTBOX, AUDIT.parent, POLICY_PATH.parent]:
    p.mkdir(parents=True, exist_ok=True)

if not POLICY_PATH.exists():
    POLICY_PATH.write_text(json.dumps(DEFAULT_POLICY, indent=2) + '\n')
if not PENDING_PATH.exists():
    PENDING_PATH.write_text('{}\n')

def now_iso():
    import datetime
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'

def audit(event):
    with AUDIT.open('a') as f:
        f.write(json.dumps(event, ensure_ascii=False) + '\n')

def load_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except Exception:
        return fallback

def write_out(request_id, payload):
    out = OUTBOX / f'{request_id}.json'
    out.write_text(json.dumps(payload, indent=2) + '\n')

def execute_action(action, args):
    cmd = ['/root/openclaw-stack/scripts/guard-email.sh', action, json.dumps(args)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    raw = (proc.stdout or '').strip() or (proc.stderr or '').strip()
    try:
        parsed = json.loads(raw) if raw else {'ok': proc.returncode == 0}
    except Exception:
        parsed = {'ok': proc.returncode == 0, 'raw': raw}
    return proc.returncode, parsed

def process_one(path):
    req = load_json(path, None)
    if not isinstance(req, dict):
        return False
    rid = req.get('requestId')
    action = req.get('action')
    args = req.get('args', {})
    who = req.get('requestedBy', 'unknown')

    if not rid or not action or not isinstance(args, dict):
        payload = {'requestId': rid or 'unknown', 'status': 'rejected', 'error': 'invalid_request', 'completedAt': now_iso()}
        if rid:
            write_out(rid, payload)
        audit({'ts': now_iso(), 'event': 'rejected', 'reason': 'invalid_request', 'request': req})
        return True

    policy = load_json(POLICY_PATH, DEFAULT_POLICY)
    decision = policy.get(action, 'rejected')

    if decision == 'rejected':
        payload = {'requestId': rid, 'status': 'rejected', 'error': 'policy_rejected', 'action': action, 'completedAt': now_iso()}
        write_out(rid, payload)
        audit({'ts': now_iso(), 'event': 'rejected', 'requestId': rid, 'action': action, 'requestedBy': who, 'reason': 'policy_rejected'})
        return True

    if decision == 'ask':
        pending = load_json(PENDING_PATH, {})
        pending[rid] = {'request': req, 'createdAt': now_iso(), 'state': 'pending_approval'}
        PENDING_PATH.write_text(json.dumps(pending, indent=2) + '\n')
        payload = {'requestId': rid, 'status': 'pending_approval', 'action': action, 'message': 'Awaiting guard approval', 'completedAt': now_iso()}
        write_out(rid, payload)
        audit({'ts': now_iso(), 'event': 'pending_approval', 'requestId': rid, 'action': action, 'requestedBy': who})
        return True

    rc, result = execute_action(action, args)
    status = 'ok' if rc == 0 else 'error'
    payload = {'requestId': rid, 'status': status, 'action': action, 'result': result, 'completedAt': now_iso()}
    write_out(rid, payload)
    audit({'ts': now_iso(), 'event': status, 'requestId': rid, 'action': action, 'requestedBy': who})
    return True


def main():
    files = sorted(INBOX.glob('*.json'), key=lambda p: p.stat().st_mtime)
    if not files:
        print('no_requests')
        return
    f = files[0]
    try:
        ok = process_one(f)
    finally:
        try:
            f.unlink(missing_ok=True)
        except Exception:
            pass
    print('processed' if ok else 'ignored')

if __name__ == '__main__':
    main()
