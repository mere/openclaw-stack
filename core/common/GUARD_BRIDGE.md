# Op and Chloe

- **Op (guard):** Admin instance with SSH access. Fix Chloe, restarts, large architectural changes. No day-to-day; no credentials.
- **Chloe (worker):** Day-to-day instance. Create all agents here. Has Bitwarden, email, webtop. User talks to Chloe for daily work; user talks to Op for admin.

Bitwarden runs in Chloe’s container; she uses **`bw`** (in PATH). Setup step 6 configures and unlocks the vault in worker state. For guard capabilities and exec approvals, see **core/guard/ROLE.md**.
