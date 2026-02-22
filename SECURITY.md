# Security

This stack is designed as a **passwordless setup**: **no secrets or passwords are stored in files on the host.** Bitwarden login and unlock are done interactively in setup step 6; only the Bitwarden server URL (`BW_SERVER`) is stored in `bitwarden.env`. Credentials live in Bitwarden (cloud or self-hosted); the guard fetches them at runtime and never writes them to disk.

## Reporting a vulnerability

If you believe you have found a security issue, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities.
2. Open a private Security Advisory in this repository (on GitHub: **Security** → **Advisories** → **New draft**), or contact the maintainers directly if you use a fork.
3. Include a clear description and steps to reproduce, if possible.
4. Allow reasonable time for a fix before any public disclosure.

## Security model

This project helps you run a two-instance OpenClaw stack with a **passwordless setup**: no secrets or passwords in files. Security-sensitive behaviour is documented in the main [README](README.md#security-model). Credentials live in Bitwarden; the worker has no direct access. Only `BW_SERVER` is stored in `bitwarden.env` on the host. Keep `stack.env` and `bitwarden.env` off the repo and restrict access on the host.
