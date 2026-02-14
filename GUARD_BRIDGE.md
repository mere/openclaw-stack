# Guard Bridge Design (Worker → Guard)

## Purpose

Provide a **safe, narrow privilege bridge** from Worker to Guard without exposing the full Guard API/CLI.

- Worker handles day-to-day assistant tasks.
- Guard handles privileged operations and secrets.
- Worker must not directly execute arbitrary Guard commands.

## Core Security Boundary

Worker requests are **untrusted inputs**.
Guard is the policy decision point.

Therefore:
- Worker does **not** declare approval requirements.
- Guard decides policy from its own rule map.
- Unknown actions are denied by default.

## Bridge Transport (v1)

Use host-backed JSON queue files (simple + auditable):

- Inbox: `/var/lib/openclaw/bridge/inbox/*.json`
- Outbox: `/var/lib/openclaw/bridge/outbox/*.json`
- Audit: `/var/lib/openclaw/bridge/audit/bridge-audit.jsonl`

Guard runner watches inbox, validates schema, evaluates policy, executes allowed action, writes result to outbox.

## Request Format (Worker → Guard)

```json
{
  "requestId": "uuid",
  "requestedBy": "worker",
  "action": "email.send",
  "args": {
    "account": "icloud",
    "to": "someone@example.com",
    "subject": "Hi",
    "body": "..."
  },
  "createdAt": "2026-02-14T22:00:00Z"
}
```

`requiresApproval` is not accepted from Worker.
If present, Guard ignores/rejects.

## Policy Map (Guard-owned)

Guard stores per-action policy values:

- `approved` → execute automatically
- `rejected` → deny automatically
- `ask` → require explicit user decision

Example map:

```json
{
  "email.list": "approved",
  "email.read": "approved",
  "email.send": "ask"
}
```

## Ask Flow (Telegram)

When policy is `ask`, Guard sends 4 inline buttons:

1. Approve
2. Reject
3. Always approve
4. Always reject

Semantics:
- **Approve**: execute this request only.
- **Reject**: reject this request only.
- **Always approve**: set policy map action → `approved`, then execute.
- **Always reject**: set policy map action → `rejected`, reject now.

The last two persist to Guard policy map.

## Email Access Model

- Bitwarden and email credentials live on Guard only.
- Himalaya runs on Guard only.
- Worker never receives raw mailbox credentials.
- Worker asks via bridge actions only.

Suggested initial actions:
- `email.list`
- `email.read`
- `email.draft`
- `email.send` (default `ask`)

## Non-goals

- No direct Worker access to `./openclaw-guard`.
- No generic remote command execution through bridge.
- No bypass of Guard policy map.
