# Scripts layout

- **`guard/`** — Run in the guard (Op) container: entrypoint, bridge server, command engine, bridge policy, `bw-with-session`.
- **`worker/`** — Used by the worker (Chloe) container: bridge client (`bridge.sh`), `bw`, `m365`, `call`, `catalog`, email/O365 setup scripts.
- **`host/`** — Run on the host: setup, sync-workspaces, Tailscale, CDP/webtop, stack health, watchdog.

Containers have PATH set so they see the right folder first (e.g. worker: `scripts/worker` then `scripts`; guard: `scripts/guard` then `scripts`).
