# No bridge

There is **no bridge** between guard and worker. The **worker never goes to the guard**—not even for credentials. Bitwarden runs **in the worker** (Chloe); she uses the **`bw`** script (in PATH) to read from the vault. Credentials and session live in worker state (`/home/node/.openclaw/secrets/`, `bitwarden-cli`). Setup step 6 configures Bitwarden for the worker. The guard is a lightweight admin with full VPS access and no tools; no day-to-day responsibilities.

For guard (Op) capabilities and exec approvals, see **core/guard/ROLE.md**.
