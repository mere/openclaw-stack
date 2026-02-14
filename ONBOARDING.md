# Onboarding Playbook

This is the practical sequence for onboarding a fresh VPS.

## 1) Clone + bootstrap

```bash
git clone https://github.com/mere/openclaw-stack.git
cd openclaw-stack
sudo ./scripts/bootstrap-vps.sh
```

During bootstrap, you can optionally enter:
- Bitwarden credentials for guard (`bitwarden.env`)
- Tailscale installation bootstrap

## 2) Start stack

```bash
sudo ./start.sh
```

## 3) Run OpenClaw setup (both instances)

```bash
docker exec -it chloe-openclaw-guard ./openclaw.mjs setup
docker exec -it chloe-openclaw-gateway ./openclaw.mjs setup
```

## 4) One-time browser login

Use webtop/noVNC, log into LinkedIn (or other sites) once, then keep using persistent CDP profile.

## 5) Verify

```bash
sudo ./healthcheck.sh
```

Expected:
- worker up
- guard up
- browser up
- CDP smoke test passes
- watchdog timer enabled

## 6) Optional Tailscale Serve URLs

After `tailscale up`, you can publish local services over tailnet HTTPS with `tailscale serve`.

---

Architecture docs: [ARCHITECTURE.md](./ARCHITECTURE.md)
