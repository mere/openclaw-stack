# Guard Bridge Design (Worker → Guard)

## Purpose

Safe privileged delegation from Worker to Guard.

- Worker submits requests.
- Guard enforces policy.
- Unknown requests are denied.

## Request schema

All requests require:
- `requestId`
- `requestedBy`
- `reason` (why Worker is asking)
- one of:
  - `action` + `args`
  - `command` (single atomic command string)

## Strict command parser (command requests)

Guard rejects non-atomic/malicious command strings, including:
- shell chaining/operators (`;`, `|`, `&&`, backticks, redirects, newlines)
- eval-style patterns (`bash -c`, `sh -c`, `python -c`, `node -e`, etc.)
- common encoding trickery (`base64`, `xxd -r`, `openssl enc`)

Command execution uses argument parsing + direct subprocess execution (`shell=False`).

## Policy model

### Action policy
`/var/lib/openclaw/guard-state/bridge/policy.json`

Values: `approved | ask | rejected`

### Command policy (regex rules)
`/var/lib/openclaw/guard-state/bridge/command-policy.json`

Rule fields:
- `id`
- `pattern` (regex)
- `decision` (`approved|ask|rejected`)

First matching rule wins. No match = rejected.

## Ask flow + wake

When decision is `ask`:
1. Request is stored in pending map.
2. Outbox receives `pending_approval`.
3. Guard runner emits a system event to wake Guard AI immediately:
   - `openclaw system event --mode now --text "...approval needed..."`

Guard AI then sends Telegram approval buttons (Approve / Reject / Always approve / Always reject).

## Approval persistence

For `always` decisions:
- action requests update `policy.json`
- command requests update matching rule decision in `command-policy.json`

## Files

- Inbox: `/var/lib/openclaw/bridge/inbox/*.json`
- Outbox: `/var/lib/openclaw/bridge/outbox/*.json`
- Pending: `/var/lib/openclaw/guard-state/bridge/pending.json`
- Audit: `/var/lib/openclaw/bridge/audit/bridge-audit.jsonl`
