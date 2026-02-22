# Guard Bridge (BW-only)

## Model

- **Bridge is BW-only.** Guard holds Bitwarden; Worker (Chloe) has no vault. She runs `bw` (a wrapper) which submits `call "bw-with-session <args>"`; Guard runs it and returns the result.
- Worker can only submit calls and read results/catalog. No extra management API layer.

## Source of truth (Guard)

- Command policy: `/home/node/.openclaw/bridge/command-policy.json` — allows only `bw-with-session` (status, list items, get item, get password). Dangerous patterns rejected.
- Policy is applied by setup (`ensure_bw_bridge_policy`) and by guard-bridge-runner defaults.

## Worker usage

- **`bw`** (in PATH): runs `bw-with-session` via bridge. Example: `bw list items`, `bw get item <id>`.
- **`call "bw-with-session <args>" --reason "Bitwarden access" [--timeout N]`** — raw bridge call.
- **`catalog`** — list allowed command patterns.

Himalaya and M365 run in the worker container; their one-time setup scripts use `bw` to fetch secrets from Guard’s Bitwarden.

## Policy decisions

- `approved` => run immediately (OpenClaw exec approvals may gate on the host).
- `rejected` => deny immediately.

## Transport (no file I/O)

- **Unix socket:** `/var/lib/openclaw/bridge/bridge.sock`. The guard runs a small server (started from the guard entrypoint); the worker connects, sends one JSON request line, receives one JSON response line. No inbox, outbox, or audit files for bridge traffic.
- **Guard state:** Command policy `/home/node/.openclaw/bridge/command-policy.json` (inside guard container).
