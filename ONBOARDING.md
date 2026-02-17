# Onboarding Playbook

## 1) Clone + run setup wizard

```bash
git clone https://github.com/mere/op-and-chloe.git
cd op-and-chloe
sudo ./scripts/setup.sh
```

Choose `Run ALL setup steps` for the default path.

## 2) Configure bots/models in wizard

Use wizard options:
- `Run configure guard (openclaw onboard)` for Op
- `Run configure worker (openclaw onboard)` for Chloe

## 3) Optional browser login

Use webtop/noVNC once for persistent site sessions.

## 4) Optional explicit verify

```bash
sudo ./healthcheck.sh
```

Expected:
- 🐯 Chloe (worker) up
- 🐕 Op (guard) up
- browser up
- CDP smoke test passes
- watchdog timer enabled

---

Architecture docs: [ARCHITECTURE.md](./ARCHITECTURE.md)
