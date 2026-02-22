# core/common

Shared reference docs used by **both** Guard and Worker. Not profile-specific.

- **GUARD_BRIDGE.md** — Op (admin, SSH) vs Chloe (day-to-day, agents + BW).
- **GUARD_POLICY_PROFILE.md** — Exec approvals for Op.

The repo is mounted at `/opt/op-and-chloe` in both containers, so these are available at `core/common/...` without any seed step. Only `core/guard` and `core/worker` are synced into workspaces by `scripts/sync-workspaces.sh`.
