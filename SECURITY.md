# Security

## Reporting a vulnerability

If you believe you have found a security issue, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities.
2. Open a private Security Advisory in this repository (on GitHub: **Security** → **Advisories** → **New draft**), or contact the maintainers directly if you use a fork.
3. Include a clear description and steps to reproduce, if possible.
4. Allow reasonable time for a fix before any public disclosure.

## Security model

This project helps you run a two-instance OpenClaw stack. Security-sensitive behaviour is documented in the main [README](README.md#security-model): credentials live in Bitwarden and guard-state; the worker has no direct access to secrets. Keep your `stack.env` and any `bitwarden.env` off the repo and restrict access on the host.
