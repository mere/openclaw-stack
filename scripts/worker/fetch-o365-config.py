#!/usr/bin/env python3
"""Fetch O365 config from guard's Bitwarden via bridge and write to worker state.
Run once in Chloe (worker) after bridge is set up. Creates secrets/o365-config.json
so m365.py can run without BW (auth login still uses device code in worker).
"""
import json
import pathlib
import subprocess
import sys

BRIDGE_SCRIPT = pathlib.Path('/opt/op-and-chloe/scripts/worker/bridge.sh')
SECRETS_DIR = pathlib.Path('/home/node/.openclaw/secrets')
CONFIG_FILE = SECRETS_DIR / 'o365-config.json'
ITEM_NAME = 'o365'


def bridge_call(command: str, reason: str, timeout: int = 60) -> dict:
    proc = subprocess.run(
        [str(BRIDGE_SCRIPT), 'call', command, '--reason', reason, '--timeout', str(timeout)],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        print(proc.stderr or proc.stdout or 'Bridge call failed', file=sys.stderr)
        raise SystemExit(2)
    data = json.loads(proc.stdout)
    if data.get('status') not in ('ok', 'error'):
        print(json.dumps(data, indent=2), file=sys.stderr)
        raise SystemExit(3)
    return data


def get_stdout_from_bridge_response(data: dict) -> str:
    result = data.get('result') or {}
    results = result.get('results') or []
    if not results:
        return ''
    return (results[-1].get('stdout') or '').strip()


def main():
    if not BRIDGE_SCRIPT.exists():
        print('bridge.sh not found', file=sys.stderr)
        raise SystemExit(1)

    # 1) List items to get O365 item id
    data = bridge_call(
        f"bw-with-session list items --search {ITEM_NAME}",
        'Fetch O365 config (list items)',
    )
    raw = get_stdout_from_bridge_response(data)
    if not raw:
        print('No stdout from bridge (list items)', file=sys.stderr)
        raise SystemExit(4)
    items = json.loads(raw)
    exact = None
    for i in items:
        if (i.get('name') or '').lower() == ITEM_NAME.lower():
            exact = i
            break
    item = exact or (items[0] if items else None)
    if not item:
        print(f'No Bitwarden item found for "{ITEM_NAME}"', file=sys.stderr)
        raise SystemExit(5)
    item_id = item['id']

    # 2) Get full item
    data = bridge_call(
        f'bw-with-session get item {item_id}',
        'Fetch O365 config (get item)',
    )
    raw = get_stdout_from_bridge_response(data)
    if not raw:
        print('No stdout from bridge (get item)', file=sys.stderr)
        raise SystemExit(6)
    full = json.loads(raw)
    fields = {
        (f.get('name') or '').strip().lower(): (f.get('value') or '').strip()
        for f in (full.get('fields') or [])
    }
    login = full.get('login') or {}
    out = {
        'tenant_id': fields.get('tenant_id') or fields.get('tenant') or '',
        'client_id': fields.get('client_id') or fields.get('application_client_id') or '',
        'user_email': fields.get('user_email') or fields.get('email') or login.get('username') or '',
    }
    if not out['tenant_id'] or not out['client_id']:
        print('O365 item missing tenant_id and/or client_id', file=sys.stderr)
        raise SystemExit(7)

    SECRETS_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(out, indent=2) + '\n')
    CONFIG_FILE.chmod(0o600)
    print(json.dumps({'ok': True, 'path': str(CONFIG_FILE), 'user_email': out.get('user_email')}))


if __name__ == '__main__':
    main()
