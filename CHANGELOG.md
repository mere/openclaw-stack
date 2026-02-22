# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org).

## [0.2.16] - 2026-02-22

### Changed

- **guard-email-setup.py: no app password file on disk.** Removed storage of the iCloud app password in `icloud-app-password.txt`. Himalaya `auth.cmd` now runs the same script in `get-password` mode so the password is fetched from Bitwarden and printed to stdout when needed; no app password is ever written to a file.

[0.2.16]: https://github.com/mere/op-and-chloe/compare/v0.2.15...v0.2.16

## [0.2.15] - 2026-02-22

### Changed

- **Bitwarden: persist session key so guard can use `bw` in any process.** Step 6 no longer runs interactive `bw unlock` in the container; it prompts for the master password on the host, passes it via a temp file (deleted immediately) into `bw unlock --raw --passwordfile`, and writes only the **session key** to `guard-state/secrets/bw-session`. The master password is never stored. `check_bitwarden_unlocked_in_guard` and `check_done bitwarden` load `BW_SESSION` from that file when present.
- **guard-email-setup.py:** Use `bw-session` file when the vault is locked (replacing `bw-master-password`). If missing or expired, fail with instructions to re-run setup step 6.
- **Docs:** README, SECURITY.md, core/guard/ROLE.md updated to state that no master password is stored and that only the session key is saved in `bw-session`.

[0.2.15]: https://github.com/mere/op-and-chloe/compare/v0.2.14...v0.2.15

## [0.2.14] - 2026-02-22

### Changed

- **Docs and instructions – passwordless setup**: State clearly everywhere that this is a **passwordless setup** and that **no secrets or passwords are stored in files** on the host. README (bullets, security model, setup/Bitwarden), SECURITY.md (opening and security model), setup wizard menu and step 6 copy, core/guard/ROLE.md (Bitwarden section), ARCHITECTURE.md, and CONTRIBUTING.md updated accordingly.

[0.2.14]: https://github.com/mere/op-and-chloe/compare/v0.2.13...v0.2.14

## [0.2.13] - 2026-02-22

### Changed

- **setup.sh (step 6 – Bitwarden)**: Simplified to a single flow: log in and unlock in the same step. Removed unattended unlock and any use of a password file; unlock is always interactive. Added `check_bitwarden_unlocked_in_guard` (status only) and `run_bitwarden_unlock_interactive` (runs `bw unlock` in guard or a temp container with guard-state mount). Step 6 now verifies login then runs interactive unlock when needed; no passwords are written to disk.
- **No passwords on host**: Setup and docs now state explicitly that no passwords are stored on the box. Only `BW_SERVER` is saved in `bitwarden.env`; login and unlock prompts clarify that the master password is not stored. Updated SECURITY.md and core/guard/ROLE.md (Bitwarden section) to match.

[0.2.13]: https://github.com/mere/op-and-chloe/compare/v0.2.12...v0.2.13

## [0.2.12] - 2026-02-21

### Fixed

- **setup.sh (repo ownership)**: Added `fix_repo_ownership()` so repo files are always writable by the runtime user (uid 1000), avoiding root-owned drift when setup is run with sudo. Op (guard) and worker can edit the repo and run scripts. The function runs at the end of every setup step and is used by `ensure_repo_writable_for_guard`. Repo path uses `STACK_DIR` or `/opt/op-and-chloe`.

[0.2.12]: https://github.com/mere/op-and-chloe/compare/v0.2.11...v0.2.12

## [0.2.11] - 2026-02-21

### Fixed

- **setup.sh (step 6 – Bitwarden verification)**: After successful login, run `chown -R 1000:1000` on the Bitwarden CLI data dir so the verification container and guard (running as node/uid 1000) can read the session when setup was run with sudo. Removed `bw config server` from the verification step so we only run `bw status`; avoids "logout required" in the verifier and matches the session created at login.

[0.2.11]: https://github.com/mere/op-and-chloe/compare/v0.2.10...v0.2.11

## [0.2.10] - 2026-02-21

### Fixed

- **setup.sh (step 6 – Bitwarden)**: Run `bw logout` before `bw config server` so the Bitwarden CLI does not fail with "Logout required before server config update" when reconfiguring server (e.g. switching .com vs .eu) or when existing session data is present. Applied in both the local-CLI and Docker paths; stderr from `bw config server` is no longer suppressed so real errors are visible.

[0.2.10]: https://github.com/mere/op-and-chloe/compare/v0.2.9...v0.2.10

## [0.2.9] - 2026-02-21

### Changed

- **update-webtop-cdp-url.sh**: Also set a **chrome** profile with the same webtop CDP (and color) so clients that default to `profile=chrome` connect to the shared webtop without client config. Primary profile remains vps-chromium; chrome is documented as a compatibility alias.
- **opch-webtop skill**: Note that the stack exposes webtop as vps-chromium and as chrome; if the client uses "chrome", that correctly points at the shared webtop on this stack.

[0.2.9]: https://github.com/mere/op-and-chloe/compare/v0.2.8...v0.2.9

## [0.2.8] - 2026-02-21

### Fixed

- **sync-workspaces.sh**: With `set -u`, `$1` was unbound when the script was run with no arguments (e.g. after git pull), causing "unbound variable" and a non-zero exit. Use `${1:-}` so the profile-arg check is safe when no args are passed.

[0.2.8]: https://github.com/mere/op-and-chloe/compare/v0.2.7...v0.2.8

## [0.2.7] - 2026-02-21

### Changed

- **Seed status (✅ Seeded)**: Now hash-based. `check_seed_done` compares a SHA256 of all seedable content under `core/<profile>` (ROLE.md + skills) to the hash stored in `workspace/.seed_hash` when sync last ran. Any change in core—new or updated skill, or ROLE.md—makes the status show ⚪ Not seeded until step 14 (or `sync-workspaces.sh`) is run again. Replaces the previous check (ROLE CORE block + skill dir names only).

### Added

- **scripts/seed-hash.py**: Computes or stores the hash of `core/<profile>`. `get <stack_dir> <profile>` prints hash; `set <stack_dir> <profile> <workspace_dir>` writes `<workspace>/.seed_hash`. Used by sync-workspaces.sh (store on seed) and setup.sh (compare for status).

[0.2.7]: https://github.com/mere/op-and-chloe/compare/v0.2.6...v0.2.7

## [0.2.6] - 2026-02-21

### Added

- **opch-webtop skill**: New worker skill (`core/worker/skills/opch-webtop/SKILL.md`) explaining the shared webtop browser: user and Chloe share one Chromium (webtop + CDP); user gets the webtop URL from Dashboard URLs in setup. Documents the login workflow: when the user asks to open a page (LinkedIn, BBC, social, etc.), Chloe opens it; if the site requires login, ask the user to open Webtop and log in there, then continue in the same session. Example workflow for "Check my messages on LinkedIn" and rules (no passwords in chat; point to Webtop for login).

### Changed

- **update-webtop-cdp-url.sh**: Reverted the "chrome" profile alias; only the vps-chromium profile is managed. Client/gateway should use the profile name the server provides (vps-chromium or default), not a server-side alias.

[0.2.6]: https://github.com/mere/op-and-chloe/compare/v0.2.5...v0.2.6

## [0.2.5] - 2026-02-21

### Fixed

- **update-webtop-cdp-url.sh**: When profile already had `color: null` or invalid value, `setdefault` did not overwrite it. Now force `prof["color"] = "#00AAFF"` when `color` is missing or not a string so one run of the script fixes the gateway config and healthcheck passes.

[0.2.5]: https://github.com/mere/op-and-chloe/compare/v0.2.4...v0.2.5

## [0.2.4] - 2026-02-21

### Fixed

- **update-webtop-cdp-url.sh**: Ensure browser profile includes `color` (e.g. `#00AAFF`) so OpenClaw config validation does not fail with "browser.profiles.vps-chromium.color: expected string, received undefined".

[0.2.4]: https://github.com/mere/op-and-chloe/compare/v0.2.3...v0.2.4

## [0.2.3] - 2026-02-21

### Fixed

- **update-webtop-cdp-url.sh**: Python SyntaxError when building `cdpUrl` — f-string expression cannot include a backslash. Script now passes `STATE_JSON`, `PROFILE_NAME`, `BIP`, and `CDP_PORT` via the environment and uses a quoted heredoc so Python reads them with `os.environ` and builds the URL without shell interpolation inside the f-string.

[0.2.3]: https://github.com/mere/op-and-chloe/compare/v0.2.2...v0.2.3

## [0.2.2] - 2026-02-21

### Fixed

- **Chloe browser tool (webtop CDP)**: Worker state `cdpUrl` was sometimes wrong or stale (e.g. 127.0.0.1:18792), so Chloe's browser tool showed `cdpReady: false` even when CDP was reachable at the browser container (e.g. 172.31.0.10:9223). Fixes applied so the correct CDP URL is written and used consistently.

### Changed

- **ensure_browser_profile** (setup.sh): When the browser container is running, calls `update-webtop-cdp-url.sh` to set `cdpUrl` from the live container IP; fallback uses `BROWSER_IPV4` from env (or 172.31.0.10) when the container is not up.
- **start.sh**: After bringing the stack up, runs `update-webtop-cdp-url.sh` when the browser container is present so every start refreshes the worker CDP URL and restarts the gateway with correct config. Loads `INSTANCE` from the env file for the browser check.
- **cdp-watchdog.sh**: After restarting the browser, runs `update-webtop-cdp-url.sh` so worker state is updated and the gateway gets the correct CDP URL on recovery.
- **README**: Added troubleshooting entry for "Chloe's browser tool shows wrong URL or cdpReady: false" with one-off fix: `sudo ./scripts/update-webtop-cdp-url.sh`.

[0.2.2]: https://github.com/mere/op-and-chloe/compare/v0.2.1...v0.2.2

## [0.2.1] - 2026-02-21

### Changed

- **Bridge docs in core/common**: Moved `GUARD_BRIDGE.md` and `GUARD_POLICY_PROFILE.md` from repo root to `core/common/` to reduce root noise. Both Guard and Worker see the repo at `/opt/op-and-chloe`, so no seed step needed. Added `core/common/README.md` documenting the shared-docs folder.
- **Skill references**: `core/guard/skills/opch-approvals/SKILL.md` and `core/worker/skills/opch-bridge/SKILL.md` now point to `core/common/GUARD_BRIDGE.md` and `core/common/GUARD_POLICY_PROFILE.md`. CONTRIBUTING.md updated to mention `core/common/` docs.

[0.2.1]: https://github.com/mere/op-and-chloe/compare/v0.2.0...v0.2.1

## [0.2.0] - 2025-02-19

### Added

- **Core roles**: Expanded Op (guard) and Chloe (worker) ROLE.md with full-stack context, approval flow, Bitwarden model (Op pre-configures tools, Chloe uses bridge only), browser/webtop access, and pre-installed tools (Himalaya, Graph mail, GoG). Chloe instructs users to "ask Op" instead of SSH for admin tasks.
- **Architecture diagrams**: Inlined component topology, approval flow, and secret-flow mermaid diagrams from ARCHITECTURE.md into both core role files.
- **Seed instructions step**: Dedicated setup step (after configure worker) to seed/refresh guard and worker instructions from `core/`. Status shows ✅ Seeded only when target ROLE.md CORE block matches current repo (so "Seeded" means up-to-date).
- **Configure Dashboards**: Renamed from "dashboard URLs". Automatically detects pending pairing requests and shows menu: Rotate gateway tokens, Approve pairing for Guard/Worker (by short id), Return to main menu. After an action (approve/rotate), stays in Configure Dashboards and refreshes so status updates without returning to main menu.
- **Pairing status in Configure Dashboards**: Displays "Pairing status: Guard: ✅ N paired / Worker: ✅ N paired" or "No devices paired yet". When CLI returns device token mismatch, shows "⚠️ Token mismatch — rotate keys (option 1) to connect" instead of a generic message.
- **Pairing completed persistence**: Main-menu step (e.g. "configure Dashboards") shows "✅ Pairing completed" via a persistent marker file (no docker calls on menu redraw). `update_pairing_status` writes/removes the file when running from Configure Dashboards and uses `docker exec -i` with resolved container names for Compose-prefixed containers.
- **DEBUG_PAIRING**: Set `DEBUG_PAIRING=1` when running setup to capture raw guard/worker devices list output into `scripts/.debug-*.txt` for parsing inspection. `scripts/.debug-*.txt` added to `.gitignore`.

### Changed

- **Pending pairing parsing**: Replaced awk/grep pipeline with Python in `pending_request_ids` and `paired_count` for reliable parsing across environments; avoid grep exit-code issues in pipelines.
- **Devices list from script**: Use `docker exec -i` (no TTY) and `resolve_container_name` so guard/worker containers are found correctly when Compose adds a project prefix (e.g. `31f2873beb14_op-and-chloe-openclaw-guard`).
- **Configure Dashboards**: Removed inline "CLI: ./openclaw-guard/worker" block (kept in help step only).

### Fixed

- Pairing status showing "No devices paired yet" when CLI failed with device token mismatch; now shows explicit token-mismatch message and points to rotate keys (option 1).
- Main menu "Pairing completed" not updating until step 13 was re-entered; persistence file allows correct status on menu redraw and across restarts.

[0.2.0]: https://github.com/mere/op-and-chloe/compare/v0.1.0...v0.2.0
