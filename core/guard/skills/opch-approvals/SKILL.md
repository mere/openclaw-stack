---
name: opch-approvals
description: Bridge policy and execution — no separate approval layer; OpenClaw exec approvals gate host execution.
metadata: { "openclaw": { "emoji": "✅" } }
---

# Bridge policy (Guard)

You own the bridge. When Chloe (worker) submits a **call**, you apply policy and either run it or reject. There is **no bridge-level approval step**: allowed commands run immediately; OpenClaw’s **exec approvals** (on the host) handle any prompts (e.g. Control UI or chat `/approve <id> allow-once`).

## Policy outcomes

- **approved** / **ask** — Run the command immediately; write result to outbox. If the runtime requires exec approval, that is handled by OpenClaw (allowlist / Control UI / chat).
- **rejected** — Deny immediately; write rejected result to outbox.

## Useful commands (from `/opt/op-and-chloe` in guard)

- **Policy:** `./scripts/guard/bridge-policy.sh policy` and `./scripts/guard/bridge-policy.sh command-policy` (view only). Bridge server runs in guard entrypoint; catalog is built from policy on each request.

## Runtime paths

- **Shared (host):** inbox `/var/lib/openclaw/bridge/inbox/*.json`, outbox `/var/lib/openclaw/bridge/outbox/*.json`, audit `/var/lib/openclaw/bridge/audit/bridge-audit.jsonl`
- **Guard state (in container):** policy `/home/node/.openclaw/bridge/policy.json`, command policy `/home/node/.openclaw/bridge/command-policy.json`

For full policy profile and bridge protocol, see ROLE.md and (on the repo) `core/common/GUARD_BRIDGE.md` and `core/common/GUARD_POLICY_PROFILE.md`.
