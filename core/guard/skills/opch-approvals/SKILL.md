---
name: opch-approvals
description: Handle bridge call requests from Chloe: apply policy, run approved commands, and ask the user via 4-button approval when policy is "ask".
metadata: { "openclaw": { "emoji": "✅" } }
---

# Bridge approvals (Guard)

You own the bridge. When Chloe (worker) submits a **call**, you apply policy and either run it, ask the user, or reject. For **ask** you send the user four inline buttons; when they reply, you parse the decision and complete the request.

## Policy outcomes

- **approved** — Run the command immediately; write result to outbox.
- **ask** — Put the request in pending; send the user an approval message with **4 buttons**; when they tap a button, parse the reply and run or reject.
- **rejected** — Deny immediately; write rejected result to outbox.

## When policy is “ask”: 4-button approval

Send the user a message that includes **four inline buttons** (e.g. via Telegram):

1. **🚀 Approve** — One-time approve this request.
2. **❌ Deny** — One-time deny.
3. **🚀 Always approve** — Approve and update policy so future similar requests are auto-approved.
4. **🛑 Always deny** — Deny and update policy so future similar requests are auto-denied.

When the user taps a button (or sends an equivalent message), you receive a callback or message. You **must** turn that into a decision and run the decision script.

## Parsing the user’s decision

Run:

```bash
/opt/op-and-chloe/scripts/guard-bridge.sh decision "<exact message text>"
```

**Accepted formats** (use request id or 8‑char prefix):

- `guard approve <requestId-or-id8>`
- `guard approve always <requestId-or-id8>`
- `guard deny <requestId-or-id8>`
- `guard deny always <requestId-or-id8>`

Match by stable identity (provider + chatId). The script updates pending state and outbox; then you can report the result.

## Useful commands (from `/opt/op-and-chloe` in guard)

- **Pending requests:** `./scripts/guard-bridge.sh pending`
- **Policy:** `./scripts/guard-bridge.sh policy` and `./scripts/guard-bridge.sh command-policy`
- **One approval cycle:** `./scripts/guard-bridge.sh run-once` (process inbox, apply policy, send buttons for “ask”, write outbox)
- **Clear all pending (reject):** `./scripts/guard-bridge.sh clear-pending`

## Runtime paths

- **Shared (host):** inbox `/var/lib/openclaw/bridge/inbox/*.json`, outbox `/var/lib/openclaw/bridge/outbox/*.json`, audit `/var/lib/openclaw/bridge/audit/bridge-audit.jsonl`
- **Guard state (in container):** policy `/home/node/.openclaw/bridge/policy.json`, command policy `/home/node/.openclaw/bridge/command-policy.json`, pending `/home/node/.openclaw/bridge/pending.json`

For full policy profile and bridge protocol, see ROLE.md and (on the repo) `core/common/GUARD_BRIDGE.md` and `core/common/GUARD_POLICY_PROFILE.md`.
