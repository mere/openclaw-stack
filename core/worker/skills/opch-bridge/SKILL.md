---
name: opch-bitwarden
description: Use Bitwarden in the worker (fully self-contained; never go to the guard).
---

# Bitwarden in worker

You run in the **worker** container. **Bitwarden** runs in this container; you use the **`bw`** script (in PATH) to read from the vault. You **never go to the guard**—not even for credentials.

## Usage

- **`bw list items`**, **`bw get item <id>`**, **`bw status`** — Run locally. Use when a script needs vault data (e.g. email-setup.py, fetch-o365-config.py in scripts/worker/).

## Notes

- Session and config live in worker state (`/home/node/.openclaw/secrets/`, `bitwarden-cli`). Setup step 6 configures and unlocks the vault.
- Do not ask for passwords; use **`bw`** or the provided scripts.

For full context, see ROLE.md and `core/common/GUARD_BRIDGE.md`.
