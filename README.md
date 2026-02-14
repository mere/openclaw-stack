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
sudo ./scripts/bootstrap-vps.sh
sudo ./start.sh
```

The bootstrap script installs Docker/Compose, prepares directories, installs systemd units, and can optionally set up Bitwarden + Tailscale.

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

## Notes

- Worker has no break-glass path; privileged actions are guard-only.
- Guard uses docker.sock + repo mount for controlled admin operations.
- Keep secrets out of git. Use `/var/lib/openclaw/guard-state/secrets/`.
