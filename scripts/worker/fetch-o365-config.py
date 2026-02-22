#!/usr/bin/env python3
"""Fetch O365 config from Bitwarden (BW runs in worker) and write to worker state.
Run once in Chloe (worker) after BW is set up. Creates secrets/o365-config.json
so m365.py can run without BW (auth login still uses device code in worker).
"""
import json
import pathlib
import subprocess
import sys

SECRETS_DIR = pathlib.Path('/home/node/.openclaw/secrets')
CONFIG_FILE = SECRETS_DIR / 'o365-config.json'
ITEM_NAME = 'o365'


def main():
    # 1) List items to get O365 item id
    proc = subprocess.run(
        ['bw', 'list', 'items', '--search', ITEM_NAME],
        capture_output=True, text=True, timeout=60,
    )
    if proc.returncode != 0:
        print(proc.stderr or proc.stdout or 'bw list items failed', file=sys.stderr)
        raise SystemExit(2)
    raw = (proc.stdout or '').strip()
    if not raw:
        print('No stdout from bw list items', file=sys.stderr)
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
    proc = subprocess.run(
        ['bw', 'get', 'item', item_id],
        capture_output=True, text=True, timeout=60,
    )
    if proc.returncode != 0:
        print(proc.stderr or proc.stdout or 'bw get item failed', file=sys.stderr)
        raise SystemExit(6)
    raw = (proc.stdout or '').strip()
    if not raw:
        print('No stdout from bw get item', file=sys.stderr)
        raise SystemExit(8)
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
