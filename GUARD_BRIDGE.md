# Guard Bridge (simple, script-first)

## Model

- Guard owns tool scripts and policies.
- Worker can only submit calls and read results/catalog.
- No extra management API layer.

## Source of truth (Guard)

- Tool scripts: `scripts/guard-*.sh`, `scripts/guard-*.py`
- Action policy: guard state policy json
- Command policy: guard state command-policy json

When you add or edit a tool script on Guard:
1) edit script
2) update policy if needed
3) run `./scripts/guard-tool-sync.sh`

## Worker usage (blocking call)

Only one mode exists: blocking `call`.

- `call "git status --short" --reason "..." --timeout 30`
- `call "himalaya envelope list -a icloud -s 20 -o json" --reason "check inbox" --timeout 120`
- `call "himalaya message read -a icloud 38400" --reason "read one email" --timeout 120`
- `call "cd /opt/op-and-chloe && git pull && ./start.sh" --reason "update stack" --timeout 600`

No action wrappers. Use direct commands through `command.run` policy map.

(Worker wrappers map to `tools/bridge` under the hood.)

## Policy decisions

- `approved` => immediate execution
- `ask` => pending approval, then execute/reject
- `rejected` => immediate deny

## Runtime files

Host shared bridge:
- Inbox: `/var/lib/openclaw/bridge/inbox/*.json`
- Outbox: `/var/lib/openclaw/bridge/outbox/*.json`
- Audit: `/var/lib/openclaw/bridge/audit/bridge-audit.jsonl`

Guard state:
- Policy: `/home/node/.openclaw/bridge/policy.json` (inside guard container)
- Command policy: `/home/node/.openclaw/bridge/command-policy.json` (inside guard container)
- Pending: `/home/node/.openclaw/bridge/pending.json` (inside guard container)


## Approval parsing + identity matching

Use strict decision text parsing:
- `^guard approve ([a-f0-9-]{8,36})$`
- `^guard approve always ([a-f0-9-]{8,36})$`
- `^guard deny ([a-f0-9-]{8,36})$`
- `^guard deny always ([a-f0-9-]{8,36})$`

Match approvals using stable identity (`provider + chatId`), not display/conversation labels.

Fallback (trusted DM only): allow requestId-only routing if identity normalization fails, and log this downgrade.


## Inline 4-button approval UX

- 🚀 Approve → `guard approve <requestId-or-id8>`
- ❌ Deny → `guard deny <requestId-or-id8>`
- 🚀 Always approve → `guard approve always <requestId>`
- 🛑 Always deny → `guard deny always <requestId>`

Decision parser command:
- `/opt/op-and-chloe/scripts/guard-bridge.sh decision "<incoming text>"`
