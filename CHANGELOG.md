# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org).

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
