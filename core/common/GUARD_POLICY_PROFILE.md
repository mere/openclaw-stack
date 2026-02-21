# Guard Policy Profile (Recommended)

This profile keeps Worker non-privileged and makes Guard the only privileged executor.

## Principles

1. Guard is the only instance with privileged host access.
2. Worker never executes arbitrary host/system commands.
3. Default for sensitive actions is **ask**.
4. High-risk commands are always **rejected**.

## Decision Levels

- `approved` → run automatically
- `ask` → require explicit user approval
- `rejected` → always deny

## Recommended action policy

### Email (Guard + Himalaya)
- `email.list` → `approved`
- `email.read` → `approved`
- `email.draft` → `ask`
- `email.send` → `ask`

### Git / release actions
- `git status`, `git log`, `git diff` → `approved`
- `git commit` → `ask`
- `git push` → `ask`

### Host / system commands
- Read-only host info (`uptime`, `df`, `ss`, `docker ps`) → `approved`
- Service restarts / config writes / package installs → `ask`
- Dangerous patterns (`rm -rf`, `mkfs`, destructive docker prune) → `rejected`

## OpenClaw native exec approvals baseline

Check current snapshot:

```bash
./openclaw-guard approvals get --json
```

Add strict allowlist entries (examples):

```bash
./openclaw-guard approvals allowlist add "/usr/bin/uptime"
./openclaw-guard approvals allowlist add "/usr/bin/df"
./openclaw-guard approvals allowlist add "/usr/bin/ss"
./openclaw-guard approvals allowlist add "/usr/bin/docker ps"
./openclaw-guard approvals allowlist add "/usr/bin/himalaya envelope list*"
./openclaw-guard approvals allowlist add "/usr/bin/himalaya message read*"
```

Keep everything else gated behind ask/approval in Guard policy flow.

## Bridge + Approval UX

Use Guard bridge policy map for `approved|ask|rejected` on action families.

For `ask`, send 4 Telegram buttons:
1. Approve
2. Reject
3. Always approve
4. Always reject

The last two update policy map persistence.

## Verification checklist

- Worker cannot run privileged host actions.
- Guard can run allowlisted read-only operations.
- Guard requires approval for send/write/state-changing operations.
- Audit log records request, decision, actor, timestamp.
