# Security

This stack does **not store your Bitwarden master password** on the host. Setup step 6 asks for it once to unlock the vault and then saves only the **session key** in **worker state** (`state/secrets/bw-session`) so Chloe can run the Bitwarden CLI. Only `BW_SERVER` is in `bitwarden.env`. Credentials live in Bitwarden; Chloe reads them at runtime via `bw`. Op (admin) has no credentials.

## Reporting a vulnerability

If you believe you have found a security issue, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities.
2. Open a private Security Advisory in this repository (on GitHub: **Security** → **Advisories** → **New draft**), or contact the maintainers directly if you use a fork.
3. Include a clear description and steps to reproduce, if possible.
4. Allow reasonable time for a fix before any public disclosure.

## Security model

This project helps you run a two-instance OpenClaw stack with a **passwordless setup**: the **Bitwarden master password is never stored** in any file. Security-sensitive behaviour is documented in the main [README](README.md#security-model). Credentials live in Bitwarden; **Chloe** holds the session (worker state) and runs `bw` in her container. **Op** is the admin instance (SSH access) with no credentials. Keep `stack.env` and secrets off the repo and restrict access on the host.

### What is in files

- **Master password:** Never written to disk. Setup uses a temp file only for the single `bw unlock` call, then removes it; only the session key is saved.
- **Session key:** Stored in **worker state** at `state/secrets/bw-session` so Chloe can run `bw` without re-unlocking. Restrict access (e.g. `chmod 600`, state dir not world-readable).
- **Op vs Chloe:** Op is admin (SSH); Chloe is day-to-day with Bitwarden and tools. They do not call each other.
