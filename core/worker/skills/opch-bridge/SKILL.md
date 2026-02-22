---
name: opch-bridge
description: Use the bridge to access Bitwarden (Op holds the vault; you use `bw`).
metadata: { "openclaw": { "emoji": "🔗" } }
---

# Bridge (Op–Chloe, BW-only)

You run in the **worker** container. **Bitwarden** lives only on Op; you access it via the **bridge** using the **`bw`** script.

## How to invoke Bitwarden

- **`bw list items`**, **`bw get item <id>`**, **`bw status`** — Run on Op via the bridge. Use when a script needs vault data (e.g. email-setup.py, fetch-o365-config.py in scripts/worker/).
- For raw control: **`call "bw-with-session <args>" --reason "Bitwarden access" [--timeout N]`** and **`catalog`** to see allowed patterns.

## Policy (Op’s side)

- Only **`bw-with-session`** commands are allowed (status, list items, get item, get password). **approved** → run; **rejected** → denied.

## Rules

- For Bitwarden, use **`bw`** (or `call "bw-with-session ..."`). Do not ask for passwords; use the bridge.
- Email (Himalaya) and M365 run **locally**; their one-time setup uses `bw` to fetch secrets from Op.
- Do **not** ask the user to SSH or run shell commands; tell them to **ask Op**.

For full bridge protocol, see ROLE.md and `core/common/GUARD_BRIDGE.md`.
