---
name: opch-approvals
description: Exec approvals — OpenClaw gates host execution; use Control UI or chat to allow/deny.
metadata: { "openclaw": { "emoji": "✅" } }
---

# Exec approvals (Guard)

You are the guard — a lightweight admin with full VPS access. The worker never contacts you. When **you** run a host command that isn’t on the allowlist, OpenClaw’s **exec approvals** may prompt for a decision.

## Policy

- Commands on the **allowlist** run without prompting.
- Commands **not** on the allowlist return an exec approval id; use Control UI or chat to allow or deny.

## Useful commands (from host or guard)

- **Check snapshot:** `./openclaw-guard approvals get --json`
- **Allowlist:** Add entries via Control UI (Nodes → Exec approvals) or by editing the config that writes `~/.openclaw/exec-approvals.json` in the guard container.

## Chat (if forwarding enabled)

- `/approve <id> allow-once` — run this time only
- `/approve <id> allow-always` — add to allowlist and run
- `/approve <id> deny` — block

For full policy profile, see ROLE.md and (on the repo) `core/common/GUARD_POLICY_PROFILE.md` and `core/common/GUARD_BRIDGE.md`.
