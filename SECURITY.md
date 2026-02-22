# Security

This stack does **not store your Bitwarden master password** on the host. Setup step 6 asks for it once to unlock the vault and then saves only the **session key** (in `guard-state/secrets/bw-session`) so the guard can run Bitwarden CLI in any process. Only `BW_SERVER` is in `bitwarden.env`. Credentials live in Bitwarden; the guard fetches them at runtime using the session key.

## Reporting a vulnerability

If you believe you have found a security issue, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities.
2. Open a private Security Advisory in this repository (on GitHub: **Security** → **Advisories** → **New draft**), or contact the maintainers directly if you use a fork.
3. Include a clear description and steps to reproduce, if possible.
4. Allow reasonable time for a fix before any public disclosure.

## Security model

This project helps you run a two-instance OpenClaw stack with a **passwordless setup**: the **Bitwarden master password is never stored** in any file. Security-sensitive behaviour is documented in the main [README](README.md#security-model). Credentials live in Bitwarden; the worker has no direct access. Only `BW_SERVER` is stored in `bitwarden.env` on the host. Keep `stack.env` and `bitwarden.env` off the repo and restrict access on the host.

### What is in files

- **Master password:** Never written to disk. Setup uses a temp file only for the single `bw unlock` call, then removes it; only the session key is saved.
- **Session key:** Stored in `guard-state/secrets/bw-session` so the guard can run `bw` without re-unlocking. Restrict access (e.g. `chmod 600`, guard-state not world-readable).
- **Bridge:** The worker talks to the guard over a **Unix socket** (`/var/lib/openclaw/bridge/bridge.sock`). Request and response are sent in memory; **nothing is written to disk** for bridge traffic. No inbox/outbox files.
