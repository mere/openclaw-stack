# Scripts layout

- **`guard/`** — Run in the guard (Op) container: entrypoint. No bridge or Bitwarden.
- **`worker/`** — Used by the worker (Chloe) container: `bw` (Bitwarden wrapper), `m365`, email/O365 setup scripts (email-setup.py, get-email-password.py, fetch-o365-config.py, m365.py).
- **`host/`** — Run on the host: setup, sync-workspaces, Tailscale, CDP/webtop, stack health, watchdog.

Containers have PATH set so they see the right folder first (e.g. worker: `scripts/worker` then `scripts`; guard: `scripts/guard` then `scripts`).
