# Guard Policy Profile (Recommended)

This profile keeps Worker non-privileged and makes Guard the only privileged executor.

## Principles

1. Guard is the only instance with privileged host access.
2. Worker never executes arbitrary host/system commands.
3. Policy allows or denies commands; **exec approvals** (OpenClaw) gate execution on the host when needed.
4. High-risk commands are always **rejected**.

## Decision Levels

- `approved` / `ask` → run (OpenClaw exec approvals may prompt on the host)
- `rejected` → always deny

Bitwarden runs in the worker; there is no bridge. Guard policy is limited to exec approvals (see below).

## OpenClaw native exec approvals

**What it is:** The OpenClaw runtime (Guard) enforces *exec approvals* on the host where commands run. When Op tries to run a command that isn’t on the allowlist, the runtime returns an **exec approval id** (e.g. `2b31540f`) and waits for a decision. Config lives in `~/.openclaw/exec-approvals.json` on the execution host (inside the guard container, so use the CLI below).

**Policy knobs (defaults):**

- **security**: `deny` | `allowlist` | `full` — allowlist = only allowlisted binaries; full = allow all (no prompts).
- **ask**: `always` | `on-miss` | `off` — on-miss = prompt only when the command is not on the allowlist.

### Where to approve a pending request (e.g. id `2b31540f`)

1. **OpenClaw Control UI** — Open the Guard dashboard (Tailscale HTTPS or loopback), go to **Nodes → Exec approvals**, find the request and choose Allow once / Always allow / Deny.
2. **Chat (if exec approval forwarding is enabled)** — In the channel that receives approval prompts, reply:
   - `/approve 2b31540f allow-once` — run this time only
   - `/approve 2b31540f allow-always` — add to allowlist and run
   - `/approve 2b31540f deny` — block

There is no CLI to approve by id; use the UI or chat.

### Auto-enable (so a command doesn’t ask again)

- **Recommended:** Add that command (or a glob) to the allowlist. Then with `ask: on-miss` it won’t prompt for that command again. Example:
  ```bash
  ./openclaw-guard approvals allowlist add "/usr/bin/uptime"
  ```
- **Allow everything (use with care):** Set exec security to `full` so all host execs are allowed without prompts. This is equivalent to “no exec approval.” Only do this in a trusted environment (e.g. dev). To change it you’d set the config that writes `~/.openclaw/exec-approvals.json` (e.g. via Control UI or by mounting/editing that file in the guard container).

### Baseline: check and add allowlist entries

Check current snapshot:

```bash
./openclaw-guard approvals get --json
```

Add strict allowlist entries (examples above). Exec approvals handle prompts.

## Verification checklist

- Worker cannot run privileged host actions.
- Guard can run allowlisted read-only operations.
- Guard runs allowed commands; OpenClaw exec approvals gate execution when not on the allowlist.
- Audit log records request, decision, actor, timestamp.
