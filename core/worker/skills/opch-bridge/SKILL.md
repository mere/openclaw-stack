---
name: opch-bridge
description: Use the Op–Chloe bridge to run privileged or authenticated commands (no credentials on worker).
metadata: { "openclaw": { "emoji": "🔗" } }
---

# Bridge (Op–Chloe)

You run in the **worker** container and have **no** credentials. Any command that needs secrets, host access, or Docker goes through the **bridge** to **Op** (guard). Op runs the command and returns only the result; you never see passwords or tokens.

## How to invoke

- **`call "<command>" --reason "<reason>" [--timeout N]`** — Submit a command; block until result or timeout.
- **`catalog`** — List allowed commands (e.g. git, himalaya, stack update).

## Policy (Op’s side)

- **approved** / **ask** — Run immediately; you get the result. (Any exec approval is handled by OpenClaw on Op’s host.)
- **rejected** — Denied immediately.

## Examples

- `call "git status --short" --reason "User asked for repo status" --timeout 30`
- `call "himalaya envelope list -a icloud -s 20 -o json" --reason "Check inbox" --timeout 120`
- `call "himalaya message read -a icloud 38400" --reason "Read one email" --timeout 120`

## Rules

- Do **not** run host/Docker/admin commands directly; always use `call`.
- Do **not** ask the user to SSH or run shell commands; tell them to **ask Op**.
- Do **not** ask for or handle passwords or API keys; Op exposes pre-authenticated commands via the bridge.

For full bridge protocol and policy details, see ROLE.md. On the repo (mounted at `/opt/op-and-chloe`): `core/common/GUARD_BRIDGE.md` and `core/common/GUARD_POLICY_PROFILE.md` have guard-side protocol and policy reference.
