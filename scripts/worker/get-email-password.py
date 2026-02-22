#!/usr/bin/env python3
"""Print iCloud app password from Bitwarden. Used as Himalaya auth.cmd in worker.
Calls bw list items + bw get item, extracts password, prints to stdout. No files."""
import json
import subprocess
import sys

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
    # Resolve item id from Bitwarden
    proc = subprocess.run(
        ['bw', 'list', 'items', '--search', BW_ITEM_NAME],
        capture_output=True, text=True, timeout=30,
    )
    if proc.returncode != 0:
        print('bw list items failed', file=sys.stderr)
        sys.exit(1)
    raw = (proc.stdout or '').strip()
    if not raw:
        sys.exit(4)
    items = json.loads(raw)
    exact = next((i for i in items if (i.get('name') or '').lower() == BW_ITEM_NAME.lower()), None)
    item_ref = exact or (items[0] if items else None)
    if not item_ref:
        sys.exit(5)
    item_id = item_ref['id']

    # Get full item and print password
    proc = subprocess.run(
        ['bw', 'get', 'item', item_id],
        capture_output=True, text=True, timeout=30,
    )
    if proc.returncode != 0:
        print('bw get item failed', file=sys.stderr)
        sys.exit(6)
    raw = (proc.stdout or '').strip()
    if not raw:
        sys.exit(8)
    item = json.loads(raw)
    print(pick_password(item), end='')


if __name__ == '__main__':
    main()
