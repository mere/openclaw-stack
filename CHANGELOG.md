# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org).

## [0.3.2] - 2026-02-22

### Added

- **opch-email skill** (`core/worker/skills/opch-email/SKILL.md`): Explains how to set up email in the worker. Microsoft → dedicated Python scripts + OAuth (`fetch-o365-config.py`, `m365 auth login`). Gmail, iCloud, and other → Himalaya (`email-setup.py`, `get-email-password.py` as auth.cmd). Documents calling `bw` over the bridge and using it for Himalaya auth or M365 config; architecture (worker, bridge, Bitwarden on Op) and step-by-step instructions included.

[0.3.2]: https://github.com/mere/op-and-chloe/compare/v0.3.1...v0.3.2

## [0.3.1] - 2026-02-22

### Changed

- **Scripts reorganized** into `scripts/guard/`, `scripts/worker/`, `scripts/host/`. Guard: entrypoint, bridge-server, bridge-runner, command-engine, bridge-policy, bw-with-session. Worker: bridge.sh, bw, m365, call, catalog, email-setup, get-email-password, fetch-o365-config, m365.py. Host: setup, sync-workspaces, CDP/webtop, stack-health, watchdog, webtop-init. Compose and all references updated; see `scripts/README.md`.
- **guard-m365.py** renamed to **scripts/worker/m365.py** (M365 runs in worker only; guard no longer has M365).
- **README:** Technical overview inlined in Components section (topology diagram, secret flow, host commands). Architecture section now points to that overview.

### Removed

- **ARCHITECTURE.md** — content inlined into README Technical overview. Obsolete approval-flow diagram and "must request through guard policies" wording already removed; doc referenced outdated behaviour.
- **CONTRIBUTING.md:** Dropped ARCHITECTURE.md from documentation list.

### Fixed

- **.gitignore:** `scripts/.debug-*.txt` → `scripts/host/.debug-*.txt` for new layout.

[0.3.1]: https://github.com/mere/op-and-chloe/compare/v0.3.0...v0.3.1

## [0.3.0] - 2026-02-22

### Added

- **Chloe (worker) runs Himalaya and M365:** Worker image `openclaw-worker-tools.Dockerfile` adds Himalaya and Python. One-time setup: `worker-email-setup.py` (Himalaya, uses bridge for BW password), `worker-fetch-o365-config.py` (O365 config from BW via bridge), then `m365 auth login` in worker.
- **Simple BW from Chloe:** Script **`bw`** in PATH runs Bitwarden on Op via the bridge (e.g. `bw list items`, `bw get item <id>`). Bridge is now **BW-only**; no himalaya/git over the bridge.

### Changed

- **Guard image:** Only Bitwarden CLI (Himalaya removed). M365 and Himalaya run in the worker container.
- **Bridge policy:** Only `bw-with-session` (status, list items, get item, get password) allowed. `ensure_m365_bridge_policy` replaced by `ensure_bw_bridge_policy`.
- **guard-m365.py:** Supports `M365_CONFIG_PATH` / `o365-config.json` in worker state so M365 can run in Chloe without BW; guard still uses Bitwarden for O365 config when file is absent.
- **Docs and ROLEs:** core/guard/ROLE.md, core/worker/ROLE.md, GUARD_BRIDGE.md, opch-bridge SKILL, README bridge section updated for BW-only bridge and local Himalaya/M365.

### Removed

- **Bridge approval layer:** No separate approval step on the bridge. OpenClaw’s fine-grained exec approvals now gate execution on the host, so the bridge no longer implements pending approval, Telegram buttons, or decision/approve/reject flows.
- **guard-bridge.sh:** Subcommands `decision`, `clear-pending`, `approve`, `reject`, and `pending` removed. Only `run-once`, `policy`, and `command-policy` remain.
- **guard-bridge-runner.py:** `PENDING_PATH`, `wake_guard_for_ask()`, and the `ask` → pending_approval path removed. Policy outcomes `approved` and `ask` both run the command immediately (exec approvals gate on the host). Fixed dead code in `execute_action()`.

### Changed

- **guard-command-engine.py:** `execute()` now allows running when decision is `ask` as well as `approved`, so policy can still use `ask` but the command runs (OpenClaw prompts when needed).
- **Docs and skills:** GUARD_BRIDGE.md, GUARD_POLICY_PROFILE.md, core/guard/ROLE.md, core/worker/ROLE.md, opch-approvals and opch-bridge SKILLs, and setup.sh `ensure_guard_approval_instructions` updated for exec-only approvals (Control UI, chat `/approve <id>`, allowlist). core/common/README.md no longer mentions approval parsing.

[0.3.0]: https://github.com/mere/op-and-chloe/compare/v0.2.22...v0.3.0

## [0.2.22] - 2026-02-22

### Added

- **.cursor/rules/critical-rules.md:** Project rules for agents (no hacks/workarounds, fix at source, simplify, passwordless credentials, tidy up, update docs).

### Changed

- **restart.sh:** Optional service name to restart a single service (e.g. `restart.sh openclaw-guard`). Uses `COMPOSE_FILE` for compose file path; with no argument, still stops and starts the full stack.

[0.2.22]: https://github.com/mere/op-and-chloe/compare/v0.2.21...v0.2.22

## [0.2.21] - 2026-02-22

### Fixed

- **Bitwarden in guard: Op now sees vault unlocked.** Root cause: setup verified unlock by running a one-off shell that loaded `BW_SESSION` from `bw-session`; Op’s commands run in processes that never had `BW_SESSION` (only in a file). Fix at source: guard loads the session into the process environment at startup via **scripts/guard-entrypoint.sh** (sets `BITWARDENCLI_APPDATA_DIR`, sources `bitwarden.env`, exports `BW_SESSION` from `bw-session` when present, then execs the real command). Compose guard `command` now runs through this entrypoint so the Node process and all children (including Op) inherit the session; plain `bw status` works without a wrapper.

[0.2.21]: https://github.com/mere/op-and-chloe/compare/v0.2.20...v0.2.21

## [0.2.20] - 2026-02-22

### Added

- **scripts/bw-with-session.sh:** Wrapper that loads the Bitwarden session from `bw-session` and runs `bw`. In the guard, use **`bw-with-session status`**, **`bw-with-session list items`**, etc., so the vault is unlocked without a password file. Guard PATH in compose now includes `/opt/op-and-chloe/scripts`; restart the guard container once to pick up the new PATH. Documented in core/guard/ROLE.md.

[0.2.20]: https://github.com/mere/op-and-chloe/compare/v0.2.19...v0.2.20

## [0.2.19] - 2026-02-22

### Fixed

- **setup.sh (step 6 – Bitwarden unlock in guard):** The password file copied into the guard container with `docker cp` was root-owned, so `bw` (running as node) could not read it and failed with EACCES. After copying, run `chown 1000:1000 /tmp/bw-pw` inside the container (as root) so the node user can read the file.

[0.2.19]: https://github.com/mere/op-and-chloe/compare/v0.2.18...v0.2.19

## [0.2.18] - 2026-02-22

### Fixed

- **setup.sh (step 6 – Bitwarden unlock):** When unlock failed, the real error was hidden. Now capture combined stdout/stderr, treat a base64-looking first line as the session key, and on failure show the Bitwarden CLI output so the user sees the actual reason (e.g. invalid password). If no password was entered (e.g. not run from a TTY), warn and tell the user to run from a terminal.

[0.2.18]: https://github.com/mere/op-and-chloe/compare/v0.2.17...v0.2.18

## [0.2.17] - 2026-02-22

### Fixed

- **setup.sh (step 6 – Bitwarden unlock):** Under `set -u`, the RETURN trap ran in the caller scope after the function returned, so the function’s local `tmp_pw` was unbound when the trap ran. Use a global `_bw_tmp_pw` for the temp file so the trap can safely remove it. Only show “Bitwarden unlocked” and run chown when the session file was actually created (i.e. when unlock succeeded).

[0.2.17]: https://github.com/mere/op-and-chloe/compare/v0.2.16...v0.2.17

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
