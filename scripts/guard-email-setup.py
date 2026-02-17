#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import sys

BW_ENV = pathlib.Path('/home/node/.openclaw/secrets/bitwarden.env')
BW_ITEM_NAME = os.environ.get('BW_EMAIL_ITEM', 'icloud')
CONF_DIR = pathlib.Path('/home/node/.config/himalaya')
PASS_DIR = pathlib.Path('/home/node/.openclaw/secrets')
PASS_FILE = PASS_DIR / 'icloud-app-password.txt'
CONF_FILE = CONF_DIR / 'config.toml'


def fail(msg, code=1):
    print(json.dumps({'ok': False, 'error': msg}))
    raise SystemExit(code)


def run(cmd, env):
    return subprocess.check_output(cmd, env=env, text=True)


def load_bw_env(env):
    if not BW_ENV.exists():
        fail('missing_bitwarden_env_file')
    for line in BW_ENV.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        env[k] = v


def ensure_bw_unlocked(env):
    st = run(['bw', 'status'], env)
    if '"status":"unauthenticated"' in st:
        subprocess.check_call(['bw', 'login', '--apikey', '--nointeraction'], env=env, stdout=subprocess.DEVNULL)
        st = run(['bw', 'status'], env)
    if '"status":"unlocked"' not in st:
        env['BW_SESSION'] = run(['bw', 'unlock', '--raw', '--passwordenv', 'BW_PASSWORD'], env).strip()


def get_item(env, name):
    items = json.loads(run(['bw', 'list', 'items', '--search', name], env))
    if not items:
        fail('bitwarden_item_not_found')
    return json.loads(run(['bw', 'get', 'item', items[0]['id']], env))


def pick_email(item):
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


def pick_password(item):
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
    fail('icloud_password_not_found_in_bw_item')


def main():
    env = os.environ.copy()
    env['PATH'] = '/home/node/.openclaw/npm-global/bin:' + env.get('PATH', '')

    load_bw_env(env)
    ensure_bw_unlocked(env)
    item = get_item(env, BW_ITEM_NAME)
    email = pick_email(item)
    app_password = pick_password(item)

    PASS_DIR.mkdir(parents=True, exist_ok=True)
    CONF_DIR.mkdir(parents=True, exist_ok=True)

    PASS_FILE.write_text(app_password + '\n')
    os.chmod(PASS_FILE, 0o600)

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
backend.auth.cmd = "cat {PASS_FILE}"

message.send.backend.type = "smtp"
message.send.backend.host = "smtp.mail.me.com"
message.send.backend.port = 587
message.send.backend.login = "{email}"
message.send.backend.auth.type = "password"
message.send.backend.auth.cmd = "cat {PASS_FILE}"
'''
    CONF_FILE.write_text(conf)
    os.chmod(CONF_FILE, 0o600)

    print(json.dumps({'ok': True, 'account': 'icloud', 'email': email, 'config': str(CONF_FILE)}))


if __name__ == '__main__':
    main()
