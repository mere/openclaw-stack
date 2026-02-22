---
name: opch-email
description: Set up and use email in the worker (Himalaya for Gmail/iCloud/other, M365 for Microsoft).
metadata: { "openclaw": { "emoji": "📧" } }
---

# Email setup (worker)

You run in the **worker** container. **Bitwarden** runs in this container; you use the **`bw`** script to read from the vault. You never go to the guard. Email clients (Himalaya and M365) run **locally**; one-time setup uses `bw` to fetch secrets from your vault.

## Which client for which provider

| Provider | Client | Setup |
|----------|--------|--------|
| **Microsoft** (Outlook, Microsoft 365) | **M365** (dedicated Python + OAuth) | Use the dedicated Python scripts and `m365 auth login` (device code). |
| **Gmail, iCloud, and any other** | **Himalaya** | Use Himalaya; auth uses a password from Bitwarden via `bw`. |

---

## Using Bitwarden (local)

- **`bw`** — Runs Bitwarden in this container (session from worker state). Use when a script needs vault data (e.g. email password, O365 config).
  - Examples: `bw list items`, `bw get item <id>`, `bw status`.

Never ask the user for passwords; use `bw` or the provided scripts.

---

## Microsoft email (M365)

Use the **dedicated Python scripts** and **OAuth** (device code in the worker).

1. **Fetch O365 config from Bitwarden** (once):  
   `python3 /opt/op-and-chloe/scripts/worker/fetch-o365-config.py`  
   This uses `bw` to get the `o365` item and writes `~/.openclaw/secrets/o365-config.json`. No raw credentials are stored in readable files; the script uses `bw` internally.

2. **Log in with M365 (OAuth)**:  
   Run **`m365 auth login`** in the worker. Follow the device-code flow (user opens URL, enters code). After that, use **`m365`** for mail/calendar (e.g. `m365 outlook mail list`, `m365 teams presence list`).

The **`m365`** command in PATH runs `scripts/worker/m365.py`, which uses the fetched O365 config when present.

---

## Gmail, iCloud, and other email (Himalaya)

Use **Himalaya**. The password is supplied via an **auth command** that uses `bw` so the password never appears in config.

1. **One-time setup** (creates Himalaya config and wires auth to Bitwarden):  
   `python3 /opt/op-and-chloe/scripts/worker/email-setup.py`  
   - The script uses **`bw`** to list and get the Bitwarden item (e.g. `icloud` or the account name you use in BW).  
   - It writes `~/.config/himalaya/config.toml` with `backend.auth.cmd` set to **`python3 /opt/op-and-chloe/scripts/worker/get-email-password.py`**.  
   - When Himalaya needs a password, it runs that script; the script uses `bw get item …` and prints the password to stdout. The password is never stored in a file.

2. **Using Himalaya**:  
   Use **`himalaya`** directly, e.g.:  
   `himalaya envelope list -a icloud -s 20 -o json`, `himalaya message read -a icloud <id>`.

For **other accounts** (e.g. Gmail), ensure the corresponding login/app-password is stored in a Bitwarden item and adjust the setup script’s search name or add support for multiple accounts; the pattern is the same: auth via **`get-email-password.py`** (or a similar script) that uses **`bw`**.

---

## Summary

- **Microsoft** → `fetch-o365-config.py` (uses `bw` to get O365 config), then `m365 auth login` (OAuth). Use `m365` for mail/calendar.
- **Gmail, iCloud, other** → `email-setup.py` (uses `bw` to get email + item id), then Himalaya with `auth.cmd` = `get-email-password.py` (which uses `bw` to get password). Use `himalaya` for mail.
- Use **`bw`** whenever a script needs something from Bitwarden; never prompt for or handle raw passwords. See **opch-bitwarden** skill and ROLE.md.
