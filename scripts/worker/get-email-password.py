#!/usr/bin/env python3
"""Print iCloud app password from guard's BW via bridge. Used as Himalaya auth.cmd in worker."""
import json
import pathlib
import subprocess
import sys

BRIDGE_SCRIPT = pathlib.Path('/opt/op-and-chloe/scripts/worker/bridge.sh')
ITEM_ID_FILE = pathlib.Path('/home/node/.openclaw/secrets/icloud-bw-item-id')
BW_ITEM_NAME = 'icloud'


def pick_password(item: dict) -> str:
    login = item.get('login') or {}
    pw = (login.get('password') or '').strip()
    if pw:
        return pw
    for f in item.get('fields') or []:
        n = (f.get('name') or '').lower()
        v = (f.get('value') or '').strip()
        if v and n in ('app_password', 'password', 'app-specific password', 'app specific password'):
            return v
    notes = (item.get('notes') or '').strip()
    if notes:
        return notes.splitlines()[0].strip()
    sys.exit(2)


def main():
    item_id = None
    if ITEM_ID_FILE.exists():
        item_id = ITEM_ID_FILE.read_text().strip()
    if not item_id:
        # Resolve via bridge: list items then get first
        proc = subprocess.run(
            [str(BRIDGE_SCRIPT), 'call', f'bw-with-session list items --search {BW_ITEM_NAME}',
             '--reason', 'Himalaya auth', '--timeout', '30'],
            capture_output=True, text=True,
        )
        if proc.returncode != 0:
            print('Bridge list items failed', file=sys.stderr)
            sys.exit(1)
        data = json.loads(proc.stdout)
        result = data.get('result') or {}
        results = result.get('results') or []
        if not results:
            print('No bridge result', file=sys.stderr)
            sys.exit(3)
        raw = (results[-1].get('stdout') or '').strip()
        if not raw:
            sys.exit(4)
        items = json.loads(raw)
        exact = next((i for i in items if (i.get('name') or '').lower() == BW_ITEM_NAME.lower()), None)
        item = exact or (items[0] if items else None)
        if not item:
            sys.exit(5)
        item_id = item['id']
        ITEM_ID_FILE.parent.mkdir(parents=True, exist_ok=True)
        ITEM_ID_FILE.write_text(item_id)
        ITEM_ID_FILE.chmod(0o600)

    proc = subprocess.run(
        [str(BRIDGE_SCRIPT), 'call', f'bw-with-session get item {item_id}',
         '--reason', 'Himalaya auth', '--timeout', '30'],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        print('Bridge get item failed', file=sys.stderr)
        sys.exit(6)
    data = json.loads(proc.stdout)
    result = data.get('result') or {}
    results = result.get('results') or []
    if not results:
        sys.exit(7)
    raw = (results[-1].get('stdout') or '').strip()
    if not raw:
        sys.exit(8)
    item = json.loads(raw)
    print(pick_password(item), end='')


if __name__ == '__main__':
    main()
