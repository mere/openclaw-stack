#!/usr/bin/env python3
"""Bridge request handling: policy check + command execution. No file I/O for request/response."""
import json
import pathlib
import subprocess
import datetime

BRIDGE_ROOT = pathlib.Path('/var/lib/openclaw/bridge')
POLICY_PATH = pathlib.Path('/home/node/.openclaw/bridge/policy.json')
CMD_POLICY_PATH = pathlib.Path('/home/node/.openclaw/bridge/command-policy.json')

DEFAULT_POLICY = {}
DEFAULT_CMD_POLICY = {
    'rules': [
        {'id': 'bw-status', 'pattern': r'^bw-with-session\s+status\b', 'decision': 'approved'},
        {'id': 'bw-list-items', 'pattern': r'^bw-with-session\s+list\s+items\b', 'decision': 'approved'},
        {'id': 'bw-get-item', 'pattern': r'^bw-with-session\s+get\s+item\b', 'decision': 'approved'},
        {'id': 'bw-get-password', 'pattern': r'^bw-with-session\s+get\s+password\b', 'decision': 'approved'},
        {'id': 'dangerous', 'pattern': r'(rm\s+-rf|mkfs|docker\s+system\s+prune)', 'decision': 'rejected'},
    ]
}


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')


def _load_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except Exception:
        return fallback


def analyze_command(command):
    engine = pathlib.Path(__file__).resolve().parent / 'command-engine.py'
    proc = subprocess.run(
        [str(engine), 'analyze', command],
        capture_output=True, text=True,
    )
    raw = (proc.stdout or '').strip() or (proc.stderr or '').strip()
    try:
        parsed = json.loads(raw) if raw else {'ok': proc.returncode == 0}
    except Exception:
        parsed = {'ok': proc.returncode == 0, 'raw': raw}
    return proc.returncode, parsed


def execute_command(command):
    engine = pathlib.Path(__file__).resolve().parent / 'command-engine.py'
    proc = subprocess.run(
        [str(engine), 'execute', command],
        capture_output=True, text=True,
    )
    raw = (proc.stdout or '').strip() or (proc.stderr or '').strip()
    try:
        parsed = json.loads(raw) if raw else {'ok': proc.returncode == 0}
    except Exception:
        parsed = {'ok': proc.returncode == 0, 'raw': raw}
    return proc.returncode, parsed


def execute_action(action, args):
    return 1, {'ok': False, 'error': 'unsupported_action'}


def handle_request(req):
    """Process one bridge request; return response dict. No file I/O."""
    if not isinstance(req, dict):
        return {'requestId': '', 'status': 'rejected', 'error': 'invalid_request', 'completedAt': now_iso()}
    rid = req.get('requestId') or ''
    who = req.get('requestedBy', 'unknown')
    reason = (req.get('reason') or '').strip()

    # Catalog: no command, return catalog payload
    if req.get('action') == 'catalog' or (reason == 'catalog' and not req.get('command')):
        return {'requestId': rid, 'status': 'ok', 'result': get_catalog(), 'completedAt': now_iso()}

    if not rid or not reason:
        return {'requestId': rid or 'unknown', 'status': 'rejected', 'error': 'invalid_request_missing_id_or_reason', 'completedAt': now_iso()}

    action = req.get('action')
    if action:
        args = req.get('args', {})
        if not isinstance(args, dict):
            return {'requestId': rid, 'status': 'rejected', 'error': 'invalid_args', 'completedAt': now_iso()}
        policy = _load_json(POLICY_PATH, DEFAULT_POLICY)
        decision = policy.get(action, 'rejected')
        matched = 'action:' + action
    else:
        command = (req.get('command') or '').strip()
        if not command:
            return {'requestId': rid, 'status': 'rejected', 'error': 'missing_command_or_reason', 'completedAt': now_iso()}
        _arc, analysis = analyze_command(command)
        if not isinstance(analysis, dict) or not analysis.get('ok'):
            return {'requestId': rid, 'status': 'rejected', 'error': 'command_analysis_failed', 'result': analysis, 'completedAt': now_iso()}
        decision = analysis.get('decision', 'rejected')
        matched_ids = analysis.get('matchedRuleIds', [])
        matched = 'command:' + ','.join([str(x) for x in matched_ids]) if matched_ids else 'command:no_match'

    if decision == 'rejected':
        return {
            'requestId': rid,
            'status': 'rejected',
            'error': 'policy_rejected',
            'matchedRule': matched,
            'completedAt': now_iso(),
        }

    if action:
        rc, result = execute_action(action, req.get('args', {}))
    else:
        rc, result = execute_command(req.get('command', ''))
    status = 'ok' if rc == 0 else 'error'
    return {'requestId': rid, 'status': status, 'matchedRule': matched, 'result': result, 'completedAt': now_iso()}


def get_catalog():
    """Build catalog dict from command policy (no file write)."""
    policy_candidates = [
        pathlib.Path('/home/node/.openclaw/bridge/command-policy.json'),
        pathlib.Path('/var/lib/openclaw/guard-state/bridge/command-policy.json'),
    ]
    rules, source = [], 'none'
    for p in policy_candidates:
        try:
            if p.exists():
                data = json.loads(p.read_text() or '{}')
                rlist = data.get('rules') if isinstance(data, dict) else None
                if isinstance(rlist, list):
                    rules = [{'id': r.get('id', ''), 'pattern': r.get('pattern', ''), 'decision': r.get('decision', 'ask'), 'description': r.get('description', '')} for r in rlist if isinstance(r, dict)]
                    source = str(p)
                    break
        except Exception:
            continue
    return {
        'version': 2,
        'generatedBy': 'guard',
        'sourcePolicy': source,
        'commands': [{'name': 'command.run', 'kind': 'command', 'policy': 'regex-map', 'reasonRequired': True, 'description': 'Run command through policy map.', 'rulesCount': len(rules)}],
        'rules': rules,
    }
