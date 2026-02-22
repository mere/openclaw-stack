#!/usr/bin/env python3
"""Configure Himalaya in worker using guard's Bitwarden via bridge. Run once in Chloe."""
import json
import os
import pathlib
import subprocess
import sys

BRIDGE_SCRIPT = pathlib.Path('/opt/op-and-chloe/scripts/worker/bridge.sh')
CONF_DIR = pathlib.Path('/home/node/.config/himalaya')
CONF_FILE = CONF_DIR / 'config.toml'
SECRETS_DIR = pathlib.Path('/home/node/.openclaw/secrets')
ITEM_ID_FILE = SECRETS_DIR / 'icloud-bw-item-id'
BW_ITEM_NAME = 'icloud'
AUTH_CMD_SCRIPT = pathlib.Path('/opt/op-and-chloe/scripts/worker/get-email-password.py')


def fail(msg, code=1):
    print(json.dumps({'ok': False, 'error': msg}))
    raise SystemExit(code)


def bridge_call(command: str, reason: str, timeout: int = 60) -> dict:
    proc = subprocess.run(
        [str(BRIDGE_SCRIPT), 'call', command, '--reason', reason, '--timeout', str(timeout)],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        fail('bridge_failed: ' + (proc.stderr or proc.stdout or 'unknown'))
    data = json.loads(proc.stdout)
    if data.get('status') not in ('ok', 'error'):
        fail('bridge_rejected')
    return data


def get_stdout(data: dict) -> str:
    result = data.get('result') or {}
    results = result.get('results') or []
    if not results:
        return ''
    return (results[-1].get('stdout') or '').strip()


def pick_email(item: dict) -> str:
    login = item.get('login') or {}
    username = (login.get('username') or '').strip()
    if '@' in username:
        return username
    for f in item.get('fields') or []:
        n = (f.get('name') or '').lower()
        v = (f.get('value') or '').strip()
        if '@' in v and n in ('email', 'user', 'username', 'account'):
            return v
    fail('icloud_email_not_found_in_bw_item')


def main():
    if not BRIDGE_SCRIPT.exists():
        fail('bridge.sh not found')

    # List items
    data = bridge_call(f'bw-with-session list items --search {BW_ITEM_NAME}', 'Email setup (list items)')
    raw = get_stdout(data)
    if not raw:
        fail('no_stdout_from_list')
    items = json.loads(raw)
    exact = next((i for i in items if (i.get('name') or '').lower() == BW_ITEM_NAME.lower()), None)
    item_ref = exact or (items[0] if items else None)
    if not item_ref:
        fail('bitwarden_item_not_found')
    item_id = item_ref['id']

    # Get full item
    data = bridge_call(f'bw-with-session get item {item_id}', 'Email setup (get item)')
    raw = get_stdout(data)
    if not raw:
        fail('no_stdout_from_get_item')
    full = json.loads(raw)
    email = pick_email(full)

    SECRETS_DIR.mkdir(parents=True, exist_ok=True)
    ITEM_ID_FILE.write_text(item_id)
    ITEM_ID_FILE.chmod(0o600)

    CONF_DIR.mkdir(parents=True, exist_ok=True)
    auth_cmd = f'python3 {AUTH_CMD_SCRIPT}'
    conf = f'''downloads-dir = "/tmp"

[accounts.icloud]
default = true
email = "{email}"
display-name = "{email}"

folder.aliases.inbox = "INBOX"
folder.aliases.sent = "Sent Messages"
folder.aliases.drafts = "Drafts"
folder.aliases.trash = "Deleted Messages"

backend.type = "imap"
backend.host = "imap.mail.me.com"
backend.port = 993
backend.login = "{email}"
backend.auth.type = "password"
backend.auth.cmd = "{auth_cmd}"

message.send.backend.type = "smtp"
message.send.backend.host = "smtp.mail.me.com"
message.send.backend.port = 587
message.send.backend.login = "{email}"
message.send.backend.auth.type = "password"
message.send.backend.auth.cmd = "{auth_cmd}"
'''
    CONF_FILE.write_text(conf)
    os.chmod(CONF_FILE, 0o600)
    print(json.dumps({'ok': True, 'account': 'icloud', 'email': email, 'config': str(CONF_FILE)}))


if __name__ == '__main__':
    main()
