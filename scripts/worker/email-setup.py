#!/usr/bin/env python3
"""One-time Himalaya setup for iCloud. Fetches email from Bitwarden, writes only config.
Password is never stored: config uses auth.cmd so Himalaya gets the password on demand via get-email-password.py."""
import json
import os
import pathlib
import subprocess
import sys

CONF_DIR = pathlib.Path('/home/node/.config/himalaya')
CONF_FILE = CONF_DIR / 'config.toml'
BW_ITEM_NAME = 'icloud'
AUTH_CMD_SCRIPT = pathlib.Path('/opt/op-and-chloe/scripts/worker/get-email-password.py')


def fail(msg, code=1):
    print(json.dumps({'ok': False, 'error': msg}))
    raise SystemExit(code)


def bw_run(*args: str, timeout: int = 60) -> str:
    proc = subprocess.run(
        ['bw'] + list(args),
        capture_output=True, text=True, timeout=timeout,
    )
    if proc.returncode != 0:
        fail('bw_failed: ' + (proc.stderr or proc.stdout or 'unknown'))
    return (proc.stdout or '').strip()


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
    raw = bw_run('list', 'items', '--search', BW_ITEM_NAME)
    if not raw:
        fail('no_stdout_from_list')
    items = json.loads(raw)
    exact = next((i for i in items if (i.get('name') or '').lower() == BW_ITEM_NAME.lower()), None)
    item_ref = exact or (items[0] if items else None)
    if not item_ref:
        fail('bitwarden_item_not_found')

    raw = bw_run('get', 'item', item_ref['id'])
    if not raw:
        fail('no_stdout_from_get_item')
    full = json.loads(raw)
    email = pick_email(full)

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
