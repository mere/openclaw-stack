#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.parse
import urllib.request

BW_ENV = pathlib.Path('/home/node/.openclaw/secrets/bitwarden.env')
BW_APPDATA = '/home/node/.openclaw/bitwarden-cli'
ITEM_NAME = os.environ.get('M365_BW_ITEM', 'o365')
TOKEN_FILE = pathlib.Path('/home/node/.openclaw/secrets/m365-token.json')
GRAPH_BASE = 'https://graph.microsoft.com/v1.0'
SCOPES = ['offline_access', 'Mail.Read', 'Calendars.Read']


def jprint(obj):
    print(json.dumps(obj, ensure_ascii=False))


def fail(code, msg, **extra):
    out = {'ok': False, 'error': msg}
    out.update(extra)
    jprint(out)
    raise SystemExit(code)


def http_json(method, url, data=None, headers=None, timeout=30):
    h = {'Accept': 'application/json'}
    if headers:
        h.update(headers)
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data).encode('utf-8')
        h['Content-Type'] = 'application/x-www-form-urlencoded'
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode('utf-8')
            return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode('utf-8', errors='replace')
        try:
            payload = json.loads(raw)
        except Exception:
            payload = {'raw': raw}
        return e.code, payload


def load_bw_env():
    if not BW_ENV.exists():
        fail(2, 'missing_bitwarden_env', path=str(BW_ENV))
    env = os.environ.copy()
    env['BITWARDENCLI_APPDATA_DIR'] = BW_APPDATA
    for line in BW_ENV.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        env[k] = v
    return env


def bw(env, *args):
    p = subprocess.run(['bw', *args], env=env, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError((p.stderr or p.stdout or '').strip())
    return (p.stdout or '').strip()


def ensure_bw_session(env):
    try:
        st = json.loads(bw(env, 'status'))
    except Exception:
        st = {'status': 'unauthenticated'}
    if st.get('status') == 'unauthenticated':
        bw(env, 'config', 'server', env.get('BW_SERVER', 'https://vault.bitwarden.com'))
        bw(env, 'login', '--apikey', '--raw')
        st = json.loads(bw(env, 'status'))
    if st.get('status') != 'unlocked':
        session = bw(env, 'unlock', '--passwordenv', 'BW_PASSWORD', '--raw')
        env['BW_SESSION'] = session
    return env


def get_o365_config():
    env = ensure_bw_session(load_bw_env())
    items = json.loads(bw(env, 'list', 'items', '--search', ITEM_NAME))
    exact = None
    for i in items:
        if (i.get('name') or '').lower() == ITEM_NAME.lower():
            exact = i
            break
    item = exact or (items[0] if items else None)
    if not item:
        fail(2, 'bitwarden_item_not_found', item=ITEM_NAME)
    full = json.loads(bw(env, 'get', 'item', item['id']))
    fields = { (f.get('name') or '').strip().lower(): (f.get('value') or '').strip() for f in (full.get('fields') or []) }
    tenant_id = fields.get('tenant_id') or fields.get('tenant')
    client_id = fields.get('client_id') or fields.get('application_client_id')
    user_email = fields.get('user_email') or fields.get('email') or (full.get('login') or {}).get('username')
    if not tenant_id or not client_id:
        fail(2, 'o365_item_missing_fields', required=['tenant_id','client_id'])
    return {'tenant_id': tenant_id, 'client_id': client_id, 'user_email': user_email}


def token_load():
    if not TOKEN_FILE.exists():
        return {}
    try:
        return json.loads(TOKEN_FILE.read_text())
    except Exception:
        return {}


def token_save(obj):
    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    TOKEN_FILE.write_text(json.dumps(obj, indent=2) + '\n')
    os.chmod(TOKEN_FILE, 0o600)


def token_valid(tok):
    exp = tok.get('expires_at', 0)
    return isinstance(exp, (int, float)) and exp > time.time() + 60 and bool(tok.get('access_token'))


def oauth_base(tenant_id):
    return f'https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0'


def refresh_token(cfg, tok):
    rt = tok.get('refresh_token')
    if not rt:
        return None
    status, payload = http_json('POST', oauth_base(cfg['tenant_id']) + '/token', data={
        'client_id': cfg['client_id'],
        'grant_type': 'refresh_token',
        'refresh_token': rt,
        'scope': ' '.join(SCOPES),
    })
    if status != 200:
        return None
    new = {
        'access_token': payload.get('access_token'),
        'refresh_token': payload.get('refresh_token', rt),
        'token_type': payload.get('token_type', 'Bearer'),
        'scope': payload.get('scope', ''),
        'expires_at': time.time() + int(payload.get('expires_in', 3600)),
        'updated_at': int(time.time()),
    }
    token_save(new)
    return new


def ensure_access_token(cfg):
    tok = token_load()
    if token_valid(tok):
        return tok['access_token']
    new = refresh_token(cfg, tok)
    if new and token_valid(new):
        return new['access_token']
    fail(3, 'm365_not_authenticated', hint='run: python3 /opt/op-and-chloe/scripts/guard-m365.py auth login')


def graph_get(path, token, query=None):
    url = GRAPH_BASE + path
    if query:
        url += '?' + urllib.parse.urlencode(query)
    status, payload = http_json('GET', url, headers={'Authorization': f'Bearer {token}'})
    if status >= 400:
        fail(4, 'graph_request_failed', status=status, response=payload)
    return payload


def cmd_auth_login(_args):
    cfg = get_o365_config()
    status, payload = http_json('POST', oauth_base(cfg['tenant_id']) + '/devicecode', data={
        'client_id': cfg['client_id'],
        'scope': ' '.join(SCOPES),
    })
    if status != 200:
        fail(2, 'device_code_request_failed', status=status, response=payload)

    device_code = payload.get('device_code')
    interval = int(payload.get('interval', 5))
    expires_in = int(payload.get('expires_in', 900))
    message = payload.get('message')

    print(json.dumps({'ok': True, 'action': 'device_login_required', 'message': message, 'expires_in': expires_in}))
    sys.stdout.flush()

    deadline = time.time() + expires_in
    while time.time() < deadline:
        time.sleep(interval)
        st, tok = http_json('POST', oauth_base(cfg['tenant_id']) + '/token', data={
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
            'client_id': cfg['client_id'],
            'device_code': device_code,
        })
        if st == 200 and tok.get('access_token'):
            out = {
                'access_token': tok.get('access_token'),
                'refresh_token': tok.get('refresh_token'),
                'token_type': tok.get('token_type', 'Bearer'),
                'scope': tok.get('scope', ''),
                'expires_at': time.time() + int(tok.get('expires_in', 3600)),
                'updated_at': int(time.time()),
            }
            token_save(out)
            jprint({'ok': True, 'status': 'authenticated', 'user_email': cfg.get('user_email')})
            return
        err = (tok.get('error') if isinstance(tok, dict) else None)
        if err in ('authorization_pending', 'slow_down'):
            if err == 'slow_down':
                interval += 2
            continue
        fail(3, 'device_login_failed', response=tok)

    fail(3, 'device_login_timeout')


def cmd_auth_status(_args):
    cfg = get_o365_config()
    tok = token_load()
    jprint({'ok': True, 'configured': True, 'user_email': cfg.get('user_email'), 'token_cached': bool(tok.get('access_token')), 'token_valid': token_valid(tok)})


def cmd_mail_list(args):
    cfg = get_o365_config()
    token = ensure_access_token(cfg)
    payload = graph_get('/me/messages', token, {
        '$top': str(args.top),
        '$select': 'id,subject,from,receivedDateTime,isRead,importance,hasAttachments',
        '$orderby': 'receivedDateTime desc'
    })
    msgs = []
    for m in payload.get('value', []):
        msgs.append({
            'id': m.get('id'),
            'subject': m.get('subject'),
            'from': (((m.get('from') or {}).get('emailAddress') or {}).get('address')),
            'received': m.get('receivedDateTime'),
            'isRead': m.get('isRead'),
            'importance': m.get('importance'),
            'hasAttachments': m.get('hasAttachments'),
        })
    jprint({'ok': True, 'items': msgs})


def cmd_mail_read(args):
    cfg = get_o365_config()
    token = ensure_access_token(cfg)
    m = graph_get(f'/me/messages/{urllib.parse.quote(args.id)}', token, {
        '$select': 'id,subject,from,toRecipients,ccRecipients,receivedDateTime,bodyPreview,body,isRead,importance'
    })
    jprint({'ok': True, 'message': m})


def cmd_calendar_events(args):
    cfg = get_o365_config()
    token = ensure_access_token(cfg)
    now = dt.datetime.now(dt.timezone.utc)
    end = now + dt.timedelta(days=args.days)
    payload = graph_get('/me/calendarView', token, {
        'startDateTime': now.isoformat(),
        'endDateTime': end.isoformat(),
        '$orderby': 'start/dateTime',
        '$top': str(args.top),
    })
    items = []
    for e in payload.get('value', []):
        items.append({
            'id': e.get('id'),
            'subject': e.get('subject'),
            'start': (e.get('start') or {}).get('dateTime'),
            'end': (e.get('end') or {}).get('dateTime'),
            'timezone': (e.get('start') or {}).get('timeZone'),
            'location': ((e.get('location') or {}).get('displayName')),
            'isAllDay': e.get('isAllDay'),
        })
    jprint({'ok': True, 'items': items})


def cmd_calendar_list(_args):
    cfg = get_o365_config()
    token = ensure_access_token(cfg)
    payload = graph_get('/me/calendars', token, {'$select': 'id,name,isDefaultCalendar,canEdit,canShare'})
    jprint({'ok': True, 'items': payload.get('value', [])})


def build_parser():
    p = argparse.ArgumentParser(description='Guard-side Microsoft 365 Graph helper')
    sub = p.add_subparsers(dest='cmd', required=True)

    a = sub.add_parser('auth')
    a_sub = a.add_subparsers(dest='auth_cmd', required=True)
    a_login = a_sub.add_parser('login'); a_login.set_defaults(fn=cmd_auth_login)
    a_status = a_sub.add_parser('status'); a_status.set_defaults(fn=cmd_auth_status)

    m = sub.add_parser('mail')
    m_sub = m.add_subparsers(dest='mail_cmd', required=True)
    m_list = m_sub.add_parser('list')
    m_list.add_argument('--top', type=int, default=20)
    m_list.set_defaults(fn=cmd_mail_list)
    m_read = m_sub.add_parser('read')
    m_read.add_argument('--id', required=True)
    m_read.set_defaults(fn=cmd_mail_read)

    c = sub.add_parser('calendar')
    c_sub = c.add_subparsers(dest='cal_cmd', required=True)
    c_events = c_sub.add_parser('events')
    c_events.add_argument('--days', type=int, default=7)
    c_events.add_argument('--top', type=int, default=50)
    c_events.set_defaults(fn=cmd_calendar_events)
    c_list = c_sub.add_parser('list')
    c_list.set_defaults(fn=cmd_calendar_list)

    return p


def main():
    parser = build_parser()
    args = parser.parse_args()
    args.fn(args)


if __name__ == '__main__':
    main()
