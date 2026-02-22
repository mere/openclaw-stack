# Scripts layout

- **`guard/`** — Run in Op (admin) container: entrypoint.
- **`worker/`** — Used by Chloe (day-to-day) container: `bw`, `m365`, email/O365 scripts (email-setup.py, get-email-password.py, fetch-o365-config.py, m365.py).
- **`host/`** — Run on the host: setup, sync-workspaces, Tailscale, CDP/webtop, stack health, watchdog.

Containers have PATH set so they see the right folder first (e.g. worker: `scripts/worker` then `scripts`; guard: `scripts/guard` then `scripts`).
