---
name: opch-email
description: Set up and use email in the worker (Himalaya for Gmail/iCloud/other, M365 for Microsoft).
metadata: { "openclaw": { "emoji": "📧" } }
---

# Email setup (worker)

You run in the **worker** container. **Bitwarden** lives only on **Op**; you access it via the **bridge** using the **`bw`** script. Email clients (Himalaya and M365) run **locally** in the worker; one-time setup uses the bridge to fetch secrets from Op’s Bitwarden.

## Which client for which provider

| Provider | Client | Setup |
|----------|--------|--------|
| **Microsoft** (Outlook, Microsoft 365) | **M365** (dedicated Python + OAuth) | Use the dedicated Python scripts and `m365 auth login` (device code). |
| **Gmail, iCloud, and any other** | **Himalaya** | Use Himalaya; auth uses a password from Bitwarden via the bridge. |

---

## Calling Bitwarden over the bridge

- **`bw`** — Wrapper that runs Bitwarden on Op via the bridge. Use when a script needs vault data (e.g. email password, O365 config).
  - Examples: `bw list items`, `bw get item <id>`, `bw status`.
- **Low-level:** **`call "bw-with-session <args>" --reason "…" [--timeout N]`** and **`catalog`** to see allowed patterns. Only `bw-with-session` commands are allowed (status, list items, get item, get password).

Never ask the user for passwords; use `bw` or the provided scripts so Op fetches from Bitwarden and returns only what’s needed.

---

## Microsoft email (M365)

Use the **dedicated Python scripts** and **OAuth** (device code in the worker).

1. **Fetch O365 config from Bitwarden** (once):  
   `python3 /opt/op-and-chloe/scripts/worker/fetch-o365-config.py`  
   This calls the bridge to get the `o365` item from Op’s Bitwarden and writes `~/.openclaw/secrets/o365-config.json` in the worker. No raw credentials are stored in files you can read; the script uses `bw` (bridge) internally.

2. **Log in with M365 (OAuth)**:  
   Run **`m365 auth login`** in the worker. Follow the device-code flow (user opens URL, enters code). After that, use **`m365`** for mail/calendar (e.g. `m365 outlook mail list`, `m365 teams presence list`).

The **`m365`** command in PATH runs `scripts/worker/m365.py`, which uses the fetched O365 config when present.

---

## Gmail, iCloud, and other email (Himalaya)

Use **Himalaya**. The password is supplied via an **auth command** that calls the bridge so the password never appears in config.

1. **One-time setup** (creates Himalaya config and wires auth to Bitwarden):  
   `python3 /opt/op-and-chloe/scripts/worker/email-setup.py`  
   - The script uses the **bridge** to list and get the Bitwarden item (e.g. `icloud` or the account name you use in BW).  
   - It writes `~/.config/himalaya/config.toml` with `backend.auth.cmd` set to **`python3 /opt/op-and-chloe/scripts/worker/get-email-password.py`**.  
   - When Himalaya needs a password, it runs that script; the script calls the bridge (`bw-with-session get item …`) and prints the password to stdout. The password is never stored in a file in the worker.

2. **Using Himalaya**:  
   Use **`himalaya`** directly, e.g.:  
   `himalaya envelope list -a icloud -s 20 -o json`, `himalaya message read -a icloud <id>`.

For **other accounts** (e.g. Gmail), ensure the corresponding login/app-password is stored in a Bitwarden item and adjust the setup script’s search name or add support for multiple accounts; the pattern is the same: auth via **`get-email-password.py`** (or a similar script) that calls **`bw`** over the bridge.

---

## Summary

- **Microsoft** → `fetch-o365-config.py` (uses bridge to get O365 config from BW), then `m365 auth login` (OAuth). Use `m365` for mail/calendar.
- **Gmail, iCloud, other** → `email-setup.py` (uses bridge to get email + item id), then Himalaya with `auth.cmd` = `get-email-password.py` (which uses bridge to get password). Use `himalaya` for mail.
- **Bridge:** Use **`bw`** whenever a script needs something from Bitwarden; never prompt for or handle raw passwords. See **opch-bridge** skill and ROLE.md for full bridge behaviour.
