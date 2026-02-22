---
name: opch-bitwarden
description: Bitwarden in Chloe — day-to-day instance has bw in PATH; use for vault access.
---

# Bitwarden (Chloe)

You are the **day-to-day instance**; create all agents here. **Bitwarden** runs in your container. Use the **`bw`** script (in PATH):

- **`bw list items`**, **`bw get item <id>`**, **`bw status`** — use when a script needs vault data (e.g. email-setup.py, fetch-o365-config.py).

Session and config live in worker state (`/home/node/.openclaw/secrets/`, `bitwarden-cli`). Setup step 6 configures and unlocks the vault. Do not ask for passwords; use **`bw`** or the provided scripts.

See ROLE.md and `core/common/GUARD_BRIDGE.md`.
