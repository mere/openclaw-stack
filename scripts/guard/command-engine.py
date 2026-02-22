#!/usr/bin/env python3
"""Guard command engine: robust multi-segment policy evaluation + execution.

Goals:
- Parse a command string into segments split by ';' and '&&'
- Evaluate each segment against ALL policy map rules
- Segment decision precedence: rejected > ask > approved
- Whole-command decision precedence: rejected > ask > approved
- Execute only when fully approved
- Built-in support for `cd` which updates cwd for subsequent segments

Policy file:
- /home/node/.openclaw/bridge/command-policy.json
  {"rules": [{"id": "...", "pattern": "...", "decision": "approved|ask|rejected"}, ...]}
"""

import argparse
import datetime
import json
import pathlib
import re
import shlex
import subprocess
import sys
from typing import Any, Tuple

CMD_POLICY_PATH = pathlib.Path('/home/node/.openclaw/bridge/command-policy.json')

DISALLOWED_PATTERNS = [
    r'\bbash\s+-c\b', r'\bsh\s+-c\b', r'\bpython\s+-c\b',
    r'\bperl\s+-e\b', r'\bnode\s+-e\b', r'\beval\b',
    r'\bbase64\b', r'\bxxd\s+-r\b', r'\bopenssl\s+enc\b'
]


def now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')


def _reject(reason: str, extra: dict[str, Any] | None = None) -> dict[str, Any]:
    out: dict[str, Any] = {'ok': False, 'error': reason, 'ts': now_iso()}
    if extra:
        out.update(extra)
    return out


def load_policy() -> dict[str, Any]:
    if not CMD_POLICY_PATH.exists():
        return {'rules': []}
    try:
        cfg = json.loads(CMD_POLICY_PATH.read_text() or '{}')
        if not isinstance(cfg, dict):
            return {'rules': []}
        if not isinstance(cfg.get('rules'), list):
            cfg['rules'] = []
        return cfg
    except Exception:
        return {'rules': []}


def tokenize_chain(command: str) -> Tuple[list[str], list[str]]:
    """Returns (segments, operators) where operators are between segments.

    Allowed operators: ';' and '&&'
    Disallowed: single '&', pipes, redirects, etc. (We reject at parse-time for safety.)
    """
    lexer = shlex.shlex(command, posix=True, punctuation_chars=';&|')
    lexer.whitespace_split = True
    lexer.commenters = ''
    raw = list(lexer)

    segments: list[str] = []
    ops: list[str] = []
    cur: list[str] = []

    i = 0
    while i < len(raw):
        t = raw[i]
        if t in (';', '&', '&&', '|'):
            if t == '&&':
                op = '&&'
            elif t == '&':
                # backgrounding not allowed
                raise ValueError('single_ampersand_not_allowed')
            elif t == '|':
                raise ValueError('pipe_not_allowed')
            else:
                op = ';'

            seg = ' '.join(cur).strip()
            if not seg:
                raise ValueError('empty_segment')
            segments.append(seg)
            ops.append(op)
            cur = []
        else:
            cur.append(t)
        i += 1

    tail = ' '.join(cur).strip()
    if not tail:
        raise ValueError('empty_segment')
    segments.append(tail)

    if len(ops) != len(segments) - 1:
        raise ValueError('parse_mismatch')

    return segments, ops


def evaluate_segment(segment: str, rules: list[dict[str, Any]]) -> dict[str, Any]:
    for pat in DISALLOWED_PATTERNS:
        if re.search(pat, segment, re.IGNORECASE):
            return {
                'segment': segment,
                'decision': 'rejected',
                'matchedRules': [{'id': 'disallowed-pattern', 'decision': 'rejected', 'pattern': pat}],
                'error': 'disallowed_pattern_detected'
            }

    matched: list[dict[str, str]] = []
    for rule in rules:
        pat = rule.get('pattern', '^$')
        try:
            if re.search(pat, segment):
                matched.append({
                    'id': rule.get('id', 'unknown'),
                    'decision': rule.get('decision', 'rejected'),
                    'pattern': pat,
                })
        except re.error:
            continue

    if not matched:
        return {
            'segment': segment,
            'decision': 'ask',
            'matchedRules': [{'id': 'no_match', 'decision': 'ask', 'pattern': ''}],
            'error': 'no_matching_policy_rule'
        }

    decisions = {m['decision'] for m in matched}
    if 'rejected' in decisions:
        d = 'rejected'
    elif 'ask' in decisions:
        d = 'ask'
    elif 'approved' in decisions:
        d = 'approved'
    else:
        d = 'rejected'

    return {'segment': segment, 'decision': d, 'matchedRules': matched}


def analyze(command: str) -> dict[str, Any]:
    command = (command or '').strip()
    if not command:
        return _reject('empty_command')

    try:
        segments, ops = tokenize_chain(command)
    except ValueError as e:
        return _reject(str(e))

    policy = load_policy()
    rules = policy.get('rules', [])
    evals = [evaluate_segment(seg, rules) for seg in segments]

    decisions = [e['decision'] for e in evals]
    if 'rejected' in decisions:
        overall = 'rejected'
    elif 'ask' in decisions:
        overall = 'ask'
    else:
        overall = 'approved'

    matched_ids: list[str] = []
    for e in evals:
        for m in e.get('matchedRules', []):
            rid = m.get('id')
            if rid and rid not in matched_ids:
                matched_ids.append(rid)

    return {
        'ok': True,
        'command': command,
        'segments': evals,
        'operators': ops,
        'decision': overall,
        'matchedRuleIds': matched_ids,
        'ts': now_iso(),
    }


def run_segment(segment: str, cwd: str):
    argv = shlex.split(segment)
    if not argv:
        return {'ok': False, 'error': 'empty_argv', 'segment': segment}, cwd, 2

    if argv[0] == 'cd':
        target = argv[1] if len(argv) > 1 else '~'
        new_cwd = pathlib.Path(target).expanduser()
        if not new_cwd.is_absolute():
            new_cwd = pathlib.Path(cwd) / new_cwd
        try:
            resolved = str(new_cwd.resolve())
        except Exception:
            resolved = str(new_cwd)
        p = pathlib.Path(resolved)
        if not p.exists() or not p.is_dir():
            return {'ok': False, 'error': 'cd_target_not_directory', 'segment': segment, 'target': target}, cwd, 1
        return {'ok': True, 'builtin': 'cd', 'cwd': resolved, 'segment': segment}, resolved, 0

    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=120, cwd=cwd)
    except FileNotFoundError:
        return {'ok': False, 'error': 'command_not_found', 'argv': argv, 'segment': segment}, cwd, 127
    except subprocess.TimeoutExpired:
        return {'ok': False, 'error': 'command_timeout', 'argv': argv, 'segment': segment}, cwd, 124

    out = {
        'ok': proc.returncode == 0,
        'argv': argv,
        'segment': segment,
        'cwd': cwd,
        'exitCode': proc.returncode,
        'stdout': (proc.stdout or '')[-6000:],
        'stderr': (proc.stderr or '')[-4000:],
    }
    return out, cwd, proc.returncode


def execute(command: str) -> dict[str, Any]:
    analysis = analyze(command)
    if not analysis.get('ok'):
        return analysis
    decision = analysis.get('decision')
    if decision not in ('approved', 'ask'):
        return {
            'ok': False,
            'error': 'command_not_fully_approved',
            'decision': decision,
            'analysis': analysis,
            'ts': now_iso(),
        }

    segments = [s['segment'] for s in analysis['segments']]
    ops = analysis['operators']

    cwd = str(pathlib.Path.cwd())
    results = []
    prev_rc = 0

    for idx, seg in enumerate(segments):
        if idx > 0 and ops[idx - 1] == '&&' and prev_rc != 0:
            results.append({'ok': False, 'segment': seg, 'skipped': True, 'reason': 'previous_failed_with_and'})
            continue

        out, cwd, rc = run_segment(seg, cwd)
        results.append(out)
        prev_rc = rc

    overall_ok = all(r.get('ok') or r.get('skipped') for r in results)
    return {
        'ok': overall_ok,
        'decision': 'approved',
        'analysis': analysis,
        'results': results,
        'finalCwd': cwd,
        'ts': now_iso(),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['analyze', 'execute'])
    ap.add_argument('command')
    args = ap.parse_args()

    if args.mode == 'analyze':
        res = analyze(args.command)
        print(json.dumps(res))
        raise SystemExit(0 if res.get('ok') else 2)

    res = execute(args.command)
    print(json.dumps(res))
    raise SystemExit(0 if res.get('ok') else 1)


if __name__ == '__main__':
    main()
