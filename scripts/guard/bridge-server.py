#!/usr/bin/env python3
"""Bridge server: Unix socket, request/response. No file I/O for requests or responses."""
import importlib.util
import json
import pathlib
import socket
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
runner_spec = importlib.util.spec_from_file_location('guard_bridge_runner', SCRIPT_DIR / 'bridge-runner.py')
runner = importlib.util.module_from_spec(runner_spec)
runner_spec.loader.exec_module(runner)

SOCKET_PATH = pathlib.Path('/var/lib/openclaw/bridge/bridge.sock')
BACKLOG = 4
RECV_SIZE = 64 * 1024


def main():
    BRIDGE_ROOT = pathlib.Path('/var/lib/openclaw/bridge')
    BRIDGE_ROOT.mkdir(parents=True, exist_ok=True)
    if SOCKET_PATH.exists():
        SOCKET_PATH.unlink()
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(str(SOCKET_PATH))
    sock.listen(BACKLOG)
    sock.settimeout(300.0)  # accept timeout so we can check for shutdown
    try:
        while True:
            try:
                conn, _ = sock.accept()
            except socket.timeout:
                continue
            try:
                with conn:
                    conn.settimeout(120.0)
                    buf = b''
                    while True:
                        chunk = conn.recv(RECV_SIZE)
                        if not chunk:
                            break
                        buf += chunk
                        if b'\n' in buf:
                            break
                    line = buf.decode('utf-8', errors='replace').split('\n')[0].strip()
                    if not line:
                        continue
                    try:
                        req = json.loads(line)
                    except json.JSONDecodeError:
                        req = {}
                    payload = runner.handle_request(req)
                    conn.sendall((json.dumps(payload) + '\n').encode('utf-8'))
            except Exception:
                pass
    finally:
        sock.close()
        if SOCKET_PATH.exists():
            SOCKET_PATH.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
