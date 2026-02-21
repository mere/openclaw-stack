# Contributing to op-and-chloe

Thank you for your interest in contributing. This document explains how to get started.

## Code of conduct

Be respectful and constructive. This project aims to make OpenClaw setup easier for everyone.

## How to contribute

- **Bug reports and feature ideas:** Open a GitHub Issue in this repository (or the issue tracker for the fork you use).
- **Documentation:** Fixes and improvements to README, ARCHITECTURE.md, `core/common/` docs (e.g. GUARD_BRIDGE.md, GUARD_POLICY_PROFILE.md), and other docs are always welcome.
- **Code and scripts:** Pull requests are welcome. Please keep changes focused and describe what problem they solve.

## Development setup

1. Clone the repo:
   ```bash
   git clone https://github.com/<owner>/op-and-chloe.git
   cd op-and-chloe
   ```
2. Use the setup wizard on a test VPS (or VM) to verify behaviour:
   ```bash
   sudo ./setup.sh
   ```
3. For script changes, run the relevant script or step from the wizard and confirm nothing breaks.

## Before you submit

- **No secrets.** Do not commit passwords, API keys, tokens, or `stack.env`. Use `config/env.example` as the template; real config stays in `/etc/openclaw/stack.env` or similar on the host.
- **Shell scripts:** Prefer POSIX-style `sh` where possible; the project uses `#!/usr/bin/env bash` for scripts that need bash features.
- **Docs:** Update README or other docs if you change behaviour or add options.

## Pull request process

1. Create a branch from `main`.
2. Make your changes and test (e.g. run `./healthcheck.sh` or the relevant script).
3. Open a PR with a short description of the change and why it’s needed.
4. Respond to any review feedback.

## License

By contributing, you agree that your contributions will be licensed under the same [MIT License](LICENSE) that covers this project.
