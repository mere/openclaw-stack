#!/usr/bin/env python3
import json, re, shlex, subprocess, sys

if len(sys.argv) < 2:
    print(json.dumps({"ok": False, "error": "missing_command"}))
    sys.exit(2)

cmd = sys.argv[1].strip()

DISALLOWED_CHARS = re.compile(r'[;|&`$><\n\r\t]')
DISALLOWED_PATTERNS = [
    r'\bbash\s+-c\b', r'\bsh\s+-c\b', r'\bpython\s+-c\b',
    r'\bperl\s+-e\b', r'\bnode\s+-e\b', r'\beval\b',
    r'\bbase64\b', r'\bxxd\s+-r\b', r'\bopenssl\s+enc\b'
]

def reject(reason):
    print(json.dumps({"ok": False, "error": reason}))
    sys.exit(3)

if not cmd:
    reject("empty_command")
if DISALLOWED_CHARS.search(cmd):
    reject("non_atomic_shell_operator_detected")
for pat in DISALLOWED_PATTERNS:
    if re.search(pat, cmd, re.IGNORECASE):
        reject("disallowed_pattern_detected")

try:
    argv = shlex.split(cmd)
except Exception:
    reject("command_parse_failed")

if not argv:
    reject("empty_argv")

try:
    proc = subprocess.run(argv, capture_output=True, text=True, timeout=120)
except FileNotFoundError:
    print(json.dumps({"ok": False, "error": "command_not_found", "argv": argv}))
    sys.exit(4)
except subprocess.TimeoutExpired:
    print(json.dumps({"ok": False, "error": "command_timeout", "argv": argv}))
    sys.exit(5)

out = {
    "ok": proc.returncode == 0,
    "argv": argv,
    "exitCode": proc.returncode,
    "stdout": (proc.stdout or "")[-6000:],
    "stderr": (proc.stderr or "")[-4000:]
}
print(json.dumps(out))
sys.exit(0 if proc.returncode == 0 else 1)
