#!/usr/bin/env python3
"""
Compute or store a deterministic hash of core/<profile> (all seedable content).
Used by sync-workspaces.sh (store on seed) and setup.sh check_seed_done (compare).

Usage:
  seed-hash.py get <stack_dir> <profile>     -> print sha256 hex digest of core/<profile>
  seed-hash.py set <stack_dir> <profile> <ws> -> compute hash, write to <ws>/.seed_hash
"""
import hashlib
import sys
from pathlib import Path


def hash_core_profile(stack_dir: Path, profile: str) -> str:
    core = stack_dir / "core" / profile
    if not core.is_dir():
        return hashlib.sha256(b"").hexdigest()
    paths = sorted(p.relative_to(core) for p in core.rglob("*") if p.is_file())
    h = hashlib.sha256()
    for rel in paths:
        p = core / rel
        h.update(str(rel).encode("utf-8") + b"\n")
        h.update(p.read_bytes())
    return h.hexdigest()


def main() -> None:
    if len(sys.argv) < 4:
        print("Usage: seed-hash.py get|set <stack_dir> <profile> [workspace_dir]", file=sys.stderr)
        sys.exit(2)
    mode = sys.argv[1].lower()
    stack_dir = Path(sys.argv[2])
    profile = sys.argv[3]
    digest = hash_core_profile(stack_dir, profile)
    if mode == "get":
        if len(sys.argv) != 4:
            print("Usage: seed-hash.py get <stack_dir> <profile>", file=sys.stderr)
            sys.exit(2)
        print(digest)
    elif mode == "set":
        if len(sys.argv) != 5:
            print("Usage: seed-hash.py set <stack_dir> <profile> <workspace_dir>", file=sys.stderr)
            sys.exit(2)
        ws = Path(sys.argv[4])
        (ws / ".seed_hash").write_text(digest + "\n", encoding="utf-8")
    else:
        print("Mode must be 'get' or 'set'", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
