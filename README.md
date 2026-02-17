# openclaw-stack

Opinionated OpenClaw deployment for a single VPS with:

- **Worker** OpenClaw instance (day-to-day tasks)
- **Guard** OpenClaw instance (privileged control-plane)
- Webtop Chromium + CDP proxy for browser automation
- Health checks + watchdog timer

See full architecture and diagrams in [ARCHITECTURE.md](./ARCHITECTURE.md).

## Quick start (new VPS)

```bash
git clone https://github.com/mere/openclaw-stack.git
cd openclaw-stack
sudo ./scripts/setup.sh   # choose "Run ALL setup steps"
sudo ./start.sh
```

The setup wizard installs Docker/Compose, prepares directories, installs systemd units, and can configure Bitwarden + Tailscale.

## First-time setup (required)

Run setup for both instances:

```bash
docker exec -it chloe-openclaw-guard ./openclaw.mjs setup
docker exec -it chloe-openclaw-gateway ./openclaw.mjs setup
```

Then verify:

```bash
sudo ./healthcheck.sh
```

## Daily ops

```bash
sudo ./start.sh
sudo ./healthcheck.sh
sudo ./stop.sh
```

## Core instructions sync (worker + guard)

This repo now carries core instruction files under:

- `core/worker/*.md`
- `core/guard/*.md`

On `start.sh` (and setup start actions), the script `scripts/sync-workspaces.sh` updates the runtime workspaces:

- `/var/lib/openclaw/workspace`
- `/var/lib/openclaw/guard-workspace`

Each managed file keeps two marker blocks:

- `<!-- CORE:BEGIN --> ... <!-- CORE:END -->` (updated from repo)
- `<!-- LOCAL:BEGIN --> ... <!-- LOCAL:END -->` (preserved local custom layer)

So repo updates refresh core instructions while keeping local edits intact.

## Notes

- Worker has no break-glass path; privileged actions are guard-only.
- Guard uses docker.sock + repo mount for controlled admin operations.
- Guard image can include extra admin CLIs (Bitwarden/Himalaya/WhatsApp CLI); worker stays minimal.
- Keep secrets out of git. Use `/var/lib/openclaw/guard-state/secrets/`.

## Privilege Bridge

Script-first model:
- Guard edits tool scripts directly (`scripts/guard-*.sh`, `scripts/guard-*.py`)
- Worker calls tools through bridge
- Guard policies decide approved/ask/rejected

Quick use (minimal syntax):

```bash
# in worker workspace (blocking call only)
call "git status --short" --reason "User asked for repo status" --timeout 30
call "himalaya envelope list -a icloud -s 20 -o json" --reason "User asked for inbox" --timeout 120
call "himalaya message read -a icloud 38400" --reason "User asked to read message" --timeout 120
call "cd /opt/openclaw-stack && git pull && ./start.sh" --reason "Update stack" --timeout 600
```

Guard maintenance:

```bash
./scripts/guard-tool-sync.sh
./scripts/guard-bridge.sh pending
./scripts/guard-bridge.sh approve <requestId> once
```

See [GUARD_BRIDGE.md](./GUARD_BRIDGE.md).


### Telegram approvals

Setup enables Telegram inline buttons (`channels.telegram.capabilities.inlineButtons=all`) for worker and guard so approval UX can use native buttons.
