# op-and-chloe

`op-and-chloe` ("openclaw-ey") is a two-instance OpenClaw stack for any VPS.

- **🐯 Chloe**: friendly day-to-day assistant (safe container)
- **🐕 Op**: operator/guard instance (admin + security approvals)
- Webtop Chromium + CDP proxy for browser automation
- Healthcheck + watchdog

See architecture details in [ARCHITECTURE.md](./ARCHITECTURE.md).

## Quick start

```bash
git clone https://github.com/mere/openclaw-stack.git
cd openclaw-stack
sudo ./scripts/setup.sh
```

Use `Run ALL setup steps` in the setup wizard.

## Daily ops

```bash
sudo ./start.sh
sudo ./stop.sh
```

Optional explicit verification:

```bash
sudo ./healthcheck.sh
```

## System diagram

```mermaid
flowchart LR
  U[User Telegram]
  C[🐯 Chloe\nWorker OpenClaw\n:18789]
  O[🐕 Op\nGuard OpenClaw\n:18790]
  B[Webtop Chromium CDP\n:9223]
  BW[(Bitwarden)]
  BR[(Bridge inbox/outbox)]
  D[/var/run/docker.sock/]
  R[/opt/openclaw-stack/]

  U --> C
  U --> O

  C --> BR
  BR --> O

  C --> B
  O --> D
  O --> R
  O --> BW

  subgraph VPS
    C
    O
    B
    BR
    D
    R
  end
```

Approval flow (blocking call):

```mermaid
sequenceDiagram
  participant User
  participant Chloe as 🐯 Chloe
  participant Op as 🐕 Op

  User->>Chloe: request task
  Chloe->>Op: call "<command>" --reason ... --timeout ...
  Op->>Op: command policy evaluation
  alt decision = approved
    Op->>Op: execute command
    Op-->>Chloe: final result
  else decision = ask
    Op->>User: approval buttons
    User->>Op: approve/deny
    alt approved
      Op->>Op: execute command
      Op-->>Chloe: final result
    else denied
      Op-->>Chloe: rejected
    end
  else decision = rejected
    Op-->>Chloe: rejected
  end
  Chloe-->>User: response
```


## Core instruction sync

Core instructions live in:

- `core/worker/*.md` (Chloe)
- `core/guard/*.md` (Op)

`scripts/sync-workspaces.sh` composes them into runtime workspaces:

- `/var/lib/openclaw/workspace`
- `/var/lib/openclaw/guard-workspace`

Managed files use two blocks:

- `<!-- CORE:BEGIN --> ... <!-- CORE:END -->` (repo-managed)
- `<!-- LOCAL:BEGIN --> ... <!-- LOCAL:END -->` (locally editable)

Core updates refresh automatically; local layer stays intact.

## Bridge model (blocking calls only)

Worker uses one bridge mode only: blocking `call`.

Examples:

```bash
call "git status --short" --reason "User asked for repo status" --timeout 30
call "himalaya envelope list -a icloud -s 20 -o json" --reason "User asked for inbox" --timeout 120
call "himalaya message read -a icloud 38400" --reason "User asked to read message" --timeout 120
call "cd /opt/openclaw-stack && git pull && ./start.sh" --reason "Update stack" --timeout 600
```

No action wrappers. Use direct commands through `command.run` policy.

## Security model

- Chloe has no direct password access.
- Credentialed operations are proxied via Op-approved commands.
- Bitwarden secrets are stored under `/var/lib/openclaw/guard-state/secrets/`.
- Prefer minimal, explicit command policy rules.
