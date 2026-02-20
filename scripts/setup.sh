#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# Persistent volume root (e.g. /mnt/volume-hel1-2); set by setup step 1 or .openclaw-volume-root
VOLUME_ROOT_FILE="$STACK_DIR/.openclaw-volume-root"
if [ -f "$VOLUME_ROOT_FILE" ] && [ -s "$VOLUME_ROOT_FILE" ]; then
  OPENCLAW_VOLUME_ROOT=$(cat "$VOLUME_ROOT_FILE" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' | head -1)
fi
ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
# Load INSTANCE from env file so we check the same container names as docker compose
if [ -f "$ENV_FILE" ]; then
  INSTANCE=$(grep -E '^INSTANCE=' "$ENV_FILE" | cut -d= -f2- | tr -d '"' | head -1)
fi
INSTANCE=${INSTANCE:-op-and-chloe}

TIGER="🐯"
OK="✅"
WARN="⚠️"

say(){ echo "$TIGER $*"; }
ok(){ echo "$OK $*"; }
warn(){ echo "$WARN $*"; }
sep(){ echo "────────────────────────────────────────────────────────"; }

guard_name="${INSTANCE}-openclaw-guard"
worker_name="${INSTANCE}-openclaw-gateway"
browser_name="${INSTANCE}-browser"
worker_cfg="/var/lib/openclaw/state/openclaw.json"
guard_cfg="/var/lib/openclaw/guard-state/openclaw.json"

welcome(){
  echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  echo "┃ 🐯 OpenClaw Setup Wizard                                   ┃"
  echo "┃ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ┃"
  echo "┃ Setup includes:                                            ┃"
  echo "┃   🖥️ Webtop browser (Chromium) for persistent logins       ┃"
  echo "┃   🐕 Op (guard) OpenClaw instance (privileged operations)  ┃"
  echo "┃   🐯 Chloe (worker) OpenClaw instance (daily tasks)        ┃"
  echo "┃   🔐 Tailscale for private network access                  ┃"
  echo "┃   🔑 Bitwarden env scaffold for secret workflow            ┃"
  echo "┃   ❤️ Healthcheck + watchdog validation                     ┃"
  echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
}

need_root(){
  if [ "$EUID" -ne 0 ]; then
    warn "Please run with sudo: sudo ./setup.sh"
    exit 1
  fi
}

container_running(){
  local name="$1"
  command -v docker >/dev/null 2>&1 || return 1
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"
}

# Status for 2-column menu display
step_status(){
  case "$1" in
    1) command -v apt-get >/dev/null 2>&1 && [ -f /etc/os-release ] && echo "✅ Ready" || echo "⚪ Not ready" ;;
    2) if [ -n "${OPENCLAW_VOLUME_ROOT:-}" ]; then echo "✅ ${OPENCLAW_VOLUME_ROOT}"; else echo "⚪ Not set"; fi ;;
    3) command -v docker >/dev/null 2>&1 && echo "✅ Installed" || echo "⚪ Not installed" ;;
    4) [ -f "$ENV_FILE" ] && echo "✅ Created" || echo "⚪ Not created" ;;
    5) check_done browser_init && echo "✅ CDP scripts installed" || echo "⚪ Not installed" ;;
    6) check_done bitwarden && echo "✅ Configured" || echo "⚪ Not configured" ;;
    7) if check_done tailscale; then tsip=$(tailscale_ip); echo "✅ Running${tsip:+ ($tsip)}"; else echo "⚪ Not running"; fi ;;
    8) container_running "$guard_name" && echo "✅ Currently running" || echo "⚪ Not running" ;;
    9) container_running "$worker_name" && echo "✅ Currently running" || echo "⚪ Not running" ;;
    10) container_running "$browser_name" && echo "✅ Currently running" || echo "⚪ Not running" ;;
    11) if [ -n "${PAIRING_COMPLETED-}" ] || [ -f "${OPENCLAW_STATE_DIR:-/var/lib/openclaw}/.pairing_completed" ]; then echo "✅ Pairing completed"; else echo "⚪ Pending pairing"; fi ;;
    12) configured_label guard ;;
    13) configured_label worker ;;
    14) check_seed_done && echo "✅ Seeded" || echo "⚪ Not seeded" ;;
    15) guard_admin_mode_enabled && echo "✅ Enabled" || echo "⚪ Disabled" ;;
    16) echo "" ;;
    17) echo "" ;;
    *) echo "—" ;;
  esac
}

# True if both guard and worker ROLE.md contain a CORE block that matches current repo core/
# (so "seeded" means up-to-date with core/, not just ever run)
check_seed_done(){
  local gws="${OPENCLAW_GUARD_WORKSPACE_DIR:-/var/lib/openclaw/guard-workspace}"
  local wws="${OPENCLAW_WORKSPACE_DIR:-/var/lib/openclaw/workspace}"
  python3 - "$STACK_DIR" "$gws" "$wws" <<'PY' || return 1
import pathlib, re, sys
stack = pathlib.Path(sys.argv[1])
gws = pathlib.Path(sys.argv[2])
wws = pathlib.Path(sys.argv[3])
def core_current(p): return p.read_text().rstrip() if p.exists() else None
def core_in_target(t): 
  if not t.exists(): return None
  m = re.search(r'<!-- CORE:BEGIN -->\s*(.*?)\s*<!-- CORE:END -->', t.read_text(), re.S)
  return m.group(1).strip() if m else None
for profile, ws in (('guard', gws), ('worker', wws)):
  core_file = stack / 'core' / profile / 'ROLE.md'
  target_file = ws / 'ROLE.md'
  want, have = core_current(core_file), core_in_target(target_file)
  if want is None or have is None or want != have:
    sys.exit(1)
sys.exit(0)
PY
}

configured_label(){
  local kind="$1"
  local file
  if [ "$kind" = "guard" ]; then file="$guard_cfg"; else file="$worker_cfg"; fi
  if [ ! -s "$file" ]; then
    echo "⚪ Not configured"
    return
  fi
  if grep -q '"gateway"' "$file" && grep -q '"mode"' "$file"; then
    echo "✅ Configured"
  else
    echo "⚪ Not configured"
  fi
}

tailscale_ip(){
  tailscale ip -4 2>/dev/null | head -n1 || true
}

tailscale_dns(){
  tailscale status --json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true
}

apply_tailscale_serve(){
  "$STACK_DIR/scripts/apply-tailscale-serve.sh" && ok "Tailscale serve: 444→guard, 443→worker, 445→webtop" || warn "Tailscale serve failed (is tailscale running?)"
}

# Sync gateway auth token into openclaw.json so gateway validates the same token we show.
# Call with: sync_gateway_tokens_to_config <worker_token> <guard_token>
sync_gateway_tokens_to_config(){
  local wt="$1" gt="$2"
  [ -z "$wt" ] && [ -z "$gt" ] && return 0
  WORKER_TKN="$wt" GUARD_TKN="$gt" python3 - <<'PY'
import json, pathlib, os
wt, gt = os.environ.get("WORKER_TKN", ""), os.environ.get("GUARD_TKN", "")
worker_cfg = pathlib.Path("/var/lib/openclaw/state/openclaw.json")
guard_cfg = pathlib.Path("/var/lib/openclaw/guard-state/openclaw.json")
if wt and worker_cfg.exists():
    d = json.loads(worker_cfg.read_text())
    d.setdefault("gateway", {}).setdefault("auth", {})["token"] = wt
    worker_cfg.write_text(json.dumps(d, indent=2) + "\n")
if gt and guard_cfg.exists():
    d = json.loads(guard_cfg.read_text())
    d.setdefault("gateway", {}).setdefault("auth", {})["token"] = gt
    guard_cfg.write_text(json.dumps(d, indent=2) + "\n")
PY
  chown 1000:1000 /var/lib/openclaw/state/openclaw.json /var/lib/openclaw/guard-state/openclaw.json 2>/dev/null || true
}

enable_tokenless_tailscale_auth(){
  python3 - <<'PY2'
import json, pathlib
paths=[pathlib.Path('/var/lib/openclaw/state/openclaw.json'), pathlib.Path('/var/lib/openclaw/guard-state/openclaw.json')]
for p in paths:
    if not p.exists() or p.stat().st_size==0:
        continue
    d=json.loads(p.read_text())
    g=d.setdefault('gateway',{})
    a=g.setdefault('auth',{})
    a['allowTailscale']=True
    g['trustedProxies']=['127.0.0.1','::1','172.31.0.1']
    p.write_text(json.dumps(d,indent=2)+"\n")
PY2
  chown 1000:1000 /var/lib/openclaw/state/openclaw.json /var/lib/openclaw/guard-state/openclaw.json 2>/dev/null || true
}

apply_tailscale_bind(){ :; }


ensure_inline_buttons(){
  python3 - <<'PY2'
import json, pathlib
paths=[pathlib.Path('/var/lib/openclaw/state/openclaw.json'), pathlib.Path('/var/lib/openclaw/guard-state/openclaw.json')]
for p in paths:
    if not p.exists() or p.stat().st_size==0:
        continue
    d=json.loads(p.read_text())
    ch=d.setdefault('channels',{}).setdefault('telegram',{})
    caps=ch.setdefault('capabilities',{})
    caps['inlineButtons']='all'
    p.write_text(json.dumps(d,indent=2)+"\n")
PY2
  chown 1000:1000 /var/lib/openclaw/state/openclaw.json /var/lib/openclaw/guard-state/openclaw.json 2>/dev/null || true
}

ensure_browser_profile(){
  python3 - <<'PY2'
import json, pathlib
worker=pathlib.Path('/var/lib/openclaw/state/openclaw.json')
guard=pathlib.Path('/var/lib/openclaw/guard-state/openclaw.json')
if worker.exists() and worker.stat().st_size>0:
    d=json.loads(worker.read_text())
    b=d.setdefault('browser',{})
    b['enabled']=True
    b['defaultProfile']='vps-chromium'
    prof=b.setdefault('profiles',{})
    p=prof.setdefault('vps-chromium',{})
    p['cdpUrl']='http://172.31.0.10:9223'
    p.setdefault('color','#00AAFF')
    worker.write_text(json.dumps(d,indent=2)+"\n")
if guard.exists() and guard.stat().st_size>0:
    d=json.loads(guard.read_text())
    d.setdefault('browser',{})['enabled']=False
    guard.write_text(json.dumps(d,indent=2)+"\n")
PY2
  chown 1000:1000 /var/lib/openclaw/state/openclaw.json /var/lib/openclaw/guard-state/openclaw.json 2>/dev/null || true
}


bitwarden_env_hash(){
  local f="$1"
  [ -f "$f" ] || return 1
  sha256sum < "$f" 2>/dev/null | cut -d' ' -f1 || openssl dgst -sha256 -r 2>/dev/null < "$f" | cut -d' ' -f1
}

verify_bitwarden_credentials(){
  local secrets_file="$1"
  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi
  if docker run --rm --env-file "$secrets_file" node:20-alpine sh -c '
    npm install -g @bitwarden/cli >/dev/null 2>&1 &&
    bw config server "$BW_SERVER" >/dev/null 2>&1 &&
    BW_CLIENTID="$BW_CLIENTID" BW_CLIENTSECRET="$BW_CLIENTSECRET" bw login --apikey --nointeraction >/dev/null 2>&1 &&
    bw status 2>/dev/null | grep -qv "unauthenticated"
  ' >/dev/null 2>&1; then
    local h
    h=$(bitwarden_env_hash "$secrets_file")
    [ -n "$h" ] && echo "$h" > "$(dirname "$secrets_file")/.bw_verified" && chmod 600 "$(dirname "$secrets_file")/.bw_verified" 2>/dev/null
    return 0
  fi
  return 1
}

step_bitwarden_secrets(){
  local secrets_dir="/var/lib/openclaw/guard-state/secrets"
  local secrets_file="$secrets_dir/bitwarden.env"
  mkdir -p "$secrets_dir"
  chmod 700 "$secrets_dir"

  if [ -f "$secrets_file" ]; then
    say "Configure Bitwarden for guard"
    say "Verifying existing credentials..."
    if verify_bitwarden_credentials "$secrets_file"; then
      ok "Bitwarden credentials verified"
      return
    fi
    warn "Previous credentials failed — re-enter them below"
    echo
  fi

  say "Configure Bitwarden for guard"
  say "We use Bitwarden to share credentials safely with OpenClaw, straight from your phone."
  say "Create a free account on https://vault.bitwarden.com or https://vault.bitwarden.eu — whichever is closer to you."
  say "Then, go to Settings → Security → Keys to create an API key."

  local cur_server=""
  local cur_email=""
  local default_choice="1"
  if [ -f "$secrets_file" ]; then
    cur_server=$(grep '^BW_SERVER=' "$secrets_file" | cut -d= -f2- || true)
    cur_email=$(grep '^BW_EMAIL=' "$secrets_file" | cut -d= -f2- || true)
    ok "Existing bitwarden.env found"
    [[ "$cur_server" == *".com"* ]] && default_choice="1" || default_choice="2"
  fi

  echo "  1) I registered on https://vault.bitwarden.com"
  echo "  2) I registered on https://vault.bitwarden.eu"
  read -r -p "$TIGER BW server [1 or 2]: " ans
  ans=${ans:-$default_choice}
  if [[ "$ans" == "1" ]]; then
    BW_SERVER="https://vault.bitwarden.com"
  else
    BW_SERVER="https://vault.bitwarden.eu"
  fi

  read -r -p "$TIGER BW client id: " BW_CLIENTID
  read -r -s -p "$TIGER BW client secret (it won't be visible in this prompt): " BW_CLIENTSECRET
  echo
  read -r -p "$TIGER BW email [${cur_email:-}]: " BW_EMAIL
  BW_EMAIL=${BW_EMAIL:-$cur_email}
  read -r -s -p "$TIGER BW master password: " BW_PASSWORD
  echo

  [ -n "$BW_CLIENTID" ] || { warn "BW client id is required"; return; }
  [ -n "$BW_CLIENTSECRET" ] || { warn "BW client secret is required"; return; }
  [ -n "$BW_EMAIL" ] || { warn "BW email is required"; return; }
  [ -n "$BW_PASSWORD" ] || { warn "BW master password is required"; return; }

  rm -f "$secrets_dir/.bw_verified"
  cat > "$secrets_file" <<EOF
BW_SERVER=$BW_SERVER
BW_CLIENTID=$BW_CLIENTID
BW_CLIENTSECRET=$BW_CLIENTSECRET
BW_PASSWORD=$BW_PASSWORD
BW_EMAIL=$BW_EMAIL
EOF

  chmod 600 "$secrets_file"
  chown 1000:1000 "$secrets_dir" "$secrets_file" 2>/dev/null || true
  ok "Saved $secrets_file"

  say "Verifying Bitwarden credentials..."
  if verify_bitwarden_credentials "$secrets_file"; then
    ok "Bitwarden credentials verified"
  else
    if command -v docker >/dev/null 2>&1; then
      warn "Bitwarden login failed — check your client id, secret, and server URL"
    else
      warn "Docker not installed — skipping verification (run step 2 first)"
    fi
  fi
}

ensure_guard_bitwarden(){
  if [ ! -f /var/lib/openclaw/guard-state/secrets/bitwarden.env ]; then
    warn "Guard Bitwarden env not found at /var/lib/openclaw/guard-state/secrets/bitwarden.env"
    return
  fi
  if docker exec "$guard_name" sh -lc 'command -v bw >/dev/null 2>&1'; then
    ok "Guard Bitwarden CLI available"
    return
  fi
  say "Installing Bitwarden CLI in guard..."
  docker exec "$guard_name" sh -lc 'npm i -g @bitwarden/cli --prefix /home/node/.openclaw/npm-global >/dev/null 2>&1 || true'
  if docker exec "$guard_name" sh -lc 'command -v bw >/dev/null 2>&1'; then
    ok "Guard Bitwarden CLI installed"
  else
    warn "Guard Bitwarden CLI install failed (can retry manually)."
  fi
}



guard_admin_mode_enabled(){
  grep -q '/var/lib/openclaw:/mnt/openclaw-data' "$STACK_DIR/compose.yml"
}

set_guard_admin_mode(){
  local mode="$1"  # on|off
  local c="$STACK_DIR/compose.yml"
  if [ "$mode" = "on" ]; then
    grep -q '/var/lib/openclaw:/mnt/openclaw-data' "$c" || sed -i '/OPENCLAW_GUARD_WORKSPACE_DIR.*workspace/a\      - /var/lib/openclaw:/mnt/openclaw-data
      - /etc/openclaw:/mnt/etc-openclaw' "$c"
    ok "Guard admin mode enabled (full host OpenClaw data/config mounted)"
  else
    sed -i '\# /var/lib/openclaw:/mnt/openclaw-data#d' "$c"
    sed -i '\# /etc/openclaw:/mnt/etc-openclaw#d' "$c"
    ok "Guard admin mode disabled (minimal mounts)"
  fi
  cd "$STACK_DIR"
  docker compose --env-file "$ENV_FILE" -f compose.yml up -d --force-recreate openclaw-guard >/dev/null || true
}

step_guard_admin_mode(){
  say "Guard admin mode"
  say "When enabled, the guard can access /var/lib/openclaw and /etc/openclaw for deep fixes and stack maintenance."
  if guard_admin_mode_enabled; then
    ok "Current: ENABLED"
    read -r -p "$TIGER Disable admin mode now? [y/N]: " ans
    case "${ans:-n}" in
      y|Y) set_guard_admin_mode off ;;
      *) ok "No changes" ;;
    esac
  else
    ok "Current: DISABLED"
    read -r -p "$TIGER Enable admin mode now? [y/N]: " ans
    case "${ans:-n}" in
      y|Y) set_guard_admin_mode on ;;
      *) ok "No changes" ;;
    esac
  fi
}



ensure_guard_approval_instructions(){
  local gws="/var/lib/openclaw/guard-workspace"
  mkdir -p "$gws"
  cat > "$gws/APPROVALS.md" <<'EOF'
# Guard Approval Flow (Telegram)

Use inline buttons first:
- 🚀 Approve -> guard approve <id>
- ❌ Deny -> guard deny <id>
- 🚀 Always approve -> guard approve always <id>
- 🛑 Always deny -> guard deny always <id>

Typed text fallback uses same strings.
Regex:
- ^guard approve ([a-f0-9]{8})$
- ^guard approve always ([a-f0-9]{8})$
- ^guard deny ([a-f0-9]{8})$
- ^guard deny always ([a-f0-9]{8})$

Execution:
- /opt/op-and-chloe/scripts/guard-bridge.sh decision "<incoming text>"
EOF
  chown 1000:1000 "$gws/APPROVALS.md" 2>/dev/null || true
}



# Injects core/guard/*.md and core/worker/*.md into guard-workspace and workspace.
# Run before starting guard/worker (steps 7–8) so containers see ROLE.md on first start,
# and before configuring them (steps 10–11) so onboarding uses the latest core.
sync_core_workspaces(){
  "$STACK_DIR/scripts/sync-workspaces.sh" >/dev/null 2>&1 || true
}

ensure_repo_writable_for_guard(){
  say "Ensure repo is writable for guard"
  say "We set permissions so the guard can edit stack scripts when needed."

  # Host repo permissions (guard runs as uid 1000 inside container)
  chown -R 1000:1000 "$STACK_DIR" 2>/dev/null || true

  # Avoid git ownership/filemode noise
  git -C "$STACK_DIR" config core.fileMode false 2>/dev/null || true
  git config --global --add safe.directory "$STACK_DIR" 2>/dev/null || true

  # Also inside guard container (path is /opt/op-and-chloe)
  if container_running "$guard_name"; then
    docker exec "$guard_name" sh -lc 'git config --global --add safe.directory /opt/op-and-chloe >/dev/null 2>&1 || true'
  fi

  ok "Repo permissions/safe.directory configured"
}

ensure_bridge_dirs(){
  mkdir -p /var/lib/openclaw/bridge/inbox /var/lib/openclaw/bridge/outbox /var/lib/openclaw/bridge/audit
  mkdir -p /var/lib/openclaw/guard-state/bridge
  chown -R 1000:1000 /var/lib/openclaw/bridge /var/lib/openclaw/guard-state/bridge 2>/dev/null || true
}

check_done(){
  local id="$1"
  case "$id" in
    docker) command -v docker >/dev/null 2>&1 ;;
    env) [ -f "$ENV_FILE" ] ;;
    browser_init) [ -f /var/lib/openclaw/browser/custom-cont-init.d/20-start-chromium-cdp ] && [ -f /var/lib/openclaw/browser/custom-cont-init.d/30-start-socat-cdp-proxy ] ;;
    running) container_running "$worker_name" && container_running "$guard_name" ;;
    tailscale) tailscale status >/dev/null 2>&1 ;;
    bitwarden)
      local bw_env="/var/lib/openclaw/guard-state/secrets/bitwarden.env"
      local bw_verified="/var/lib/openclaw/guard-state/secrets/.bw_verified"
      [ -f "$bw_env" ] || return 1
      grep -q '^BW_SERVER=' "$bw_env" || return 1
      grep -q '^BW_CLIENTID=' "$bw_env" || return 1
      grep -q '^BW_CLIENTSECRET=' "$bw_env" || return 1
      grep -q '^BW_EMAIL=' "$bw_env" || return 1
      grep -q '^BW_PASSWORD=' "$bw_env" || return 1
      if [ -f "$bw_verified" ]; then
        local want_h got_h
        want_h=$(bitwarden_env_hash "$bw_env")
        got_h=$(cat "$bw_verified" 2>/dev/null)
        [ -n "$want_h" ] && [ "$want_h" = "$got_h" ] && return 0
      fi
      container_running "$guard_name" || return 1
      docker exec "$guard_name" sh -lc '
        set -e
        command -v bw >/dev/null 2>&1
        . /home/node/.openclaw/secrets/bitwarden.env
        [ -n "$BW_SERVER" ] && [ -n "$BW_CLIENTID" ] && [ -n "$BW_CLIENTSECRET" ] && [ -n "$BW_EMAIL" ] && [ -n "$BW_PASSWORD" ]
        bw config server "$BW_SERVER" >/dev/null 2>&1
        BW_CLIENTID="$BW_CLIENTID" BW_CLIENTSECRET="$BW_CLIENTSECRET" bw login --apikey --nointeraction >/dev/null 2>&1 || true
        bw status >/tmp/bw-status.json 2>/dev/null || exit 1
        grep -q '"status":"unauthenticated"' /tmp/bw-status.json && exit 1 || exit 0
      ' >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

step_volume_root(){
  say "Step 2: OpenClaw data location (persistent volume)"
  say "On a VPS with a persistent volume, choose where OpenClaw config and state should live."
  echo
  # Build menu: 0 = back, 1..n = /mnt/* dirs, last = default location
  local idx=0
  local -a options=()
  local -a paths=()
  options+=("Return to main menu")
  paths+=("")
  if [ -d /mnt ]; then
    local d
    for d in /mnt/*/; do
      [ -d "$d" ] || continue
      d=${d%/}
      options+=("$d")
      paths+=("$d")
    done
  fi
  options+=("Default location (no volume): /var/lib/openclaw and /etc/openclaw")
  paths+=("default")
  echo "  Current: ${OPENCLAW_VOLUME_ROOT:-<default>}"
  echo
  local i=0
  while [ "$i" -lt "${#options[@]}" ]; do
    printf "  %d. %s\n" "$i" "${options[$i]}"
    i=$((i + 1))
  done
  echo
  read -r -p "$TIGER Select [0-$(( ${#options[@]} - 1 ))]: " pick
  if ! [[ "$pick" =~ ^[0-9]+$ ]] || [ "$pick" -lt 0 ] || [ "$pick" -ge "${#options[@]}" ]; then
    warn "Invalid choice"
    return 0
  fi
  if [ "$pick" -eq 0 ]; then
    say "No change."
    return 0
  fi
  local chosen_path="${paths[$pick]}"
  if [ "$chosen_path" = "default" ]; then
    rm -f "$VOLUME_ROOT_FILE"
    unset OPENCLAW_VOLUME_ROOT
    ok "Using default location: /var/lib/openclaw and /etc/openclaw (no persistent volume)"
    return 0
  fi
  echo "$chosen_path" > "$VOLUME_ROOT_FILE"
  OPENCLAW_VOLUME_ROOT=$chosen_path
  ok "OpenClaw data will use: $OPENCLAW_VOLUME_ROOT"
  say "Run step 4 (environment) next to create dirs and symlinks there."
}

step_preflight(){
  say "Step 1: Preflight checks"
  say "We verify your host is ready (Ubuntu/Debian, disk space) before proceeding."
  command -v apt-get >/dev/null
  . /etc/os-release
  ok "Host OS: $PRETTY_NAME"
  ok "Disk free on /: $(df -h / | awk 'NR==2 {print $4}')"
}

step_docker(){
  say "Step 3: Docker + Compose"
  say "We use Docker to run the guard, worker and browser as safe, isolated containers."
  if check_done docker; then ok "Docker already installed"; return; fi
  say "Installing Docker..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y ca-certificates curl gnupg >/dev/null
  install -m 0755 -d /etc/apt/keyrings
  [ -f /etc/apt/keyrings/docker.gpg ] || { curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; chmod a+r /etc/apt/keyrings/docker.gpg; }
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y >/dev/null
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
  systemctl enable --now docker >/dev/null 2>&1 || true
  ok "Docker installed"
}

step_env(){
  say "Step 4: State dirs + environment"
  say "We create directories and an env file so your config and state survive restarts."
  if [ -n "${OPENCLAW_VOLUME_ROOT:-}" ]; then
    local etc_dest="$OPENCLAW_VOLUME_ROOT/openclaw/etc/openclaw"
    local lib_dest="$OPENCLAW_VOLUME_ROOT/openclaw/var/lib/openclaw"
    mkdir -p "$etc_dest" "$lib_dest"/{state,workspace,browser,guard-state,guard-workspace}
    chown -R 1000:1000 "$lib_dest"
    if [ ! -L /etc/openclaw ] && [ -e /etc/openclaw ] && [ "$(readlink -f /etc/openclaw 2>/dev/null)" != "$(readlink -f "$etc_dest" 2>/dev/null)" ]; then
      warn "/etc/openclaw already exists and is not a symlink; skipping symlink (data stays under /etc/openclaw)"
    else
      ln -snf "$etc_dest" /etc/openclaw
    fi
    if [ ! -L /var/lib/openclaw ] && [ -e /var/lib/openclaw ] && [ "$(readlink -f /var/lib/openclaw 2>/dev/null)" != "$(readlink -f "$lib_dest" 2>/dev/null)" ]; then
      warn "/var/lib/openclaw already exists and is not a symlink; skipping symlink (data stays under /var/lib/openclaw)"
    else
      ln -snf "$lib_dest" /var/lib/openclaw
    fi
    ok "Created dirs under $OPENCLAW_VOLUME_ROOT and linked /etc/openclaw, /var/lib/openclaw"
  else
    mkdir -p /etc/openclaw /var/lib/openclaw/{state,workspace,browser,guard-state,guard-workspace}
    chown -R 1000:1000 /var/lib/openclaw/state /var/lib/openclaw/workspace /var/lib/openclaw/browser /var/lib/openclaw/guard-state /var/lib/openclaw/workspace
  fi
  if [ ! -f "$ENV_FILE" ]; then
    cp "$STACK_DIR/config/env.example" "$ENV_FILE"
    sed -i "s#^OPENCLAW_GATEWAY_TOKEN=.*#OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)#" "$ENV_FILE"
    sed -i "s#^OPENCLAW_GUARD_GATEWAY_TOKEN=.*#OPENCLAW_GUARD_GATEWAY_TOKEN=$(openssl rand -hex 24)#" "$ENV_FILE"
    sed -i "s#^OPENCLAW_STACK_DIR=.*#OPENCLAW_STACK_DIR=$STACK_DIR#" "$ENV_FILE"
    ok "Created $ENV_FILE with fresh gateway tokens"
  else
    ok "Env already present: $ENV_FILE"
  fi
  echo
  echo "Created:"
  echo "  /etc/openclaw/"
  echo "  /var/lib/openclaw/guard-state"
  echo "  /var/lib/openclaw/guard-workspace"
  echo "  /var/lib/openclaw/state"
  echo "  /var/lib/openclaw/workspace"
  echo "  /var/lib/openclaw/browser"
  echo "  $ENV_FILE"
}

step_browser_init(){
  say "Step 5: Browser CDP init scripts"
  say "We install scripts so Chromium starts with remote-debugging on port 9222, proxied to 9223 for automation."
  local browser_dir="/var/lib/openclaw/browser"
  mkdir -p "$browser_dir/custom-cont-init.d"
  install -m 0755 "$STACK_DIR/scripts/webtop-init/20-start-chromium-cdp" "$browser_dir/custom-cont-init.d/20-start-chromium-cdp"
  install -m 0755 "$STACK_DIR/scripts/webtop-init/30-start-socat-cdp-proxy" "$browser_dir/custom-cont-init.d/30-start-socat-cdp-proxy"
  chown -R 1000:1000 "$browser_dir/custom-cont-init.d"
  ok "CDP init scripts installed"

  say "CDP watchdog (systemd timer)"
  say "We install a timer that restarts the browser container if CDP becomes unreachable."
  install -m 0644 "$STACK_DIR/systemd/openclaw-cdp-watchdog.timer" /etc/systemd/system/
  sed "s#/opt/op-and-chloe#$STACK_DIR#g" "$STACK_DIR/systemd/openclaw-cdp-watchdog.service" > /etc/systemd/system/openclaw-cdp-watchdog.service
  systemctl daemon-reload
  systemctl enable --now openclaw-cdp-watchdog.timer 2>/dev/null || true
  ok "CDP watchdog timer installed and enabled"
}

step_tailscale(){
  say "Step 7: Tailscale setup (opinionated default)"
  say "We use Tailscale so you can access the dashboards privately over your tailnet, without exposing ports to the internet."
  if check_done tailscale; then
    local tsip
    tsip=$(tailscale_ip)
    ok "Tailscale already running"
    ok "Tailnet IP: ${tsip}"
    apply_tailscale_serve && ok "Configured HTTPS Tailscale dashboard endpoints"
    enable_tokenless_tailscale_auth && ok "Applied Tailscale auth compatibility settings"
    return
  fi
  read -r -p "$TIGER Install Tailscale now? [Y/n]: " ans
  if [[ "$ans" =~ ^[Nn]$ ]]; then return; fi
  curl -fsSL https://tailscale.com/install.sh | sh >/dev/null
  ok "Tailscale installed"
  say "Log in to Tailscale to join this machine to your tailnet."
  say "Get an auth key from: https://login.tailscale.com/admin/settings/keys"
  read -r -p "$TIGER Paste auth key (or Enter to run 'tailscale up' interactively): " authkey
  if [ -n "$authkey" ]; then
    tailscale up --authkey="$authkey" && ok "Tailscale joined tailnet" || warn "Tailscale up failed"
  else
    say "Running 'tailscale up' — follow the prompts (browser or URL) to authenticate."
    tailscale up || warn "Run 'tailscale up' manually when ready."
  fi
  if check_done tailscale; then
    apply_tailscale_serve && ok "Configured HTTPS Tailscale dashboard endpoints"
    enable_tokenless_tailscale_auth && ok "Applied Tailscale auth compatibility settings"
  else
    say "After tailscale up succeeds, run option 7 again to configure HTTPS endpoints."
  fi
}

step_start_guard(){
  sync_core_workspaces
  say "Start guard service"
  say "The guard oversees privileged operations and approves Chloe's requests for credentials and tools."
  if container_running "$guard_name"; then ok "Guard already running"; return; fi
  cd "$STACK_DIR"
  docker compose --env-file "$ENV_FILE" -f compose.yml up -d openclaw-guard
  ok "Guard started"
}

step_start_worker(){
  sync_core_workspaces
  say "Start worker service"
  say "The worker is your main assistant — you'll chat with it daily and run tasks through it."
  if container_running "$worker_name"; then ok "Worker already running"; return; fi
  cd "$STACK_DIR"
  docker compose --env-file "$ENV_FILE" -f compose.yml up -d openclaw-gateway
  ok "Worker started"
}

step_start_browser(){
  say "Start browser service"
  say "The webtop runs a Chromium browser with a persistent profile, so Chloe can log into sites and automate them."
  if container_running "$browser_name"; then ok "Browser already running"; return; fi
  cd "$STACK_DIR"
  docker compose --env-file "$ENV_FILE" -f compose.yml up -d browser
  ok "Browser started"
}

step_start_all(){
  sync_core_workspaces
  ensure_repo_writable_for_guard
  ensure_browser_profile
  ensure_inline_buttons
  say "Start full stack"
  say "This starts all three services together so the stack is ready."
  STACK_DIR="$STACK_DIR" ENV_FILE="$ENV_FILE" "$STACK_DIR/start.sh"
  ok "Start sequence finished"
}

step_verify(){
  say "Run healthcheck"
  say "We run health checks to confirm everything is working."
  STACK_DIR="$STACK_DIR" "$STACK_DIR/healthcheck.sh" || true
  ok "Healthcheck executed"
}

step_seed_instructions(){
  say "Seed guard / worker instructions"
  say "Copies the latest role text from core/guard and core/worker into the guard and worker workspaces. Run this after a git pull or when you edit core/ to refresh Op and Chloe instructions."
  "$STACK_DIR/scripts/sync-workspaces.sh"
  ok "Guard and worker workspaces updated from core/"
}

title_case_name(){ local n="$1"; echo "${n^}"; }

step_configure_guard(){
  local pretty
  pretty=$(title_case_name "$INSTANCE")
  "$STACK_DIR/openclaw-guard" config set gateway.port 18790 >/dev/null 2>&1 || true
  "$STACK_DIR/openclaw-guard" config set gateway.bind loopback >/dev/null 2>&1 || true
  say "Run configure guard"
  say "The guard oversees privileged operations — connect a model and Telegram bot for approvals."
  echo
  sep
  echo "Tips for guard onboarding:"
  echo "  1. Select QuickStart."
  echo "  2. If you already pay for ChatGPT, we recommend: OpenAI (Codex OAuth + API key)"
  echo "  3. Select: OpenAI Codex (ChatGPT OAuth)"
  echo "  4. After you log in to OpenAI, you may see a \"This site can't be reached\" page — that's expected. Simply copy the URL from the browser and paste it into the terminal when asked."
  echo "  5. Default Model: Keep current"
  echo "  6. Select channel: we recommend Telegram (Bot API). Install Telegram on your phone if you don't have it yet."
  echo "  7. Follow the instructions and paste back the Telegram token."
  echo
  echo "Suggested bot name: ${pretty}-guard-bot"
  echo
  echo "┌────────────────────────────────────────────────────────┐"
  echo "│ ⚠️  If the onboard script exits early, run this to     │"
  echo "│     launch it again: ./openclaw-guard onboard          │"
  echo "└────────────────────────────────────────────────────────┘"
  echo
  read -r -p "$TIGER Start guard onboarding now? [Y/n]: " go
  if [[ ! "$go" =~ ^[Nn]$ ]]; then
    if ! container_running "$guard_name"; then
      warn "Guard container is not running. Run step 7 first, then try again."
      return
    fi
    echo
    say "Launching guard onboarding in this terminal (not a subprocess). When you're done, run: sudo ./scripts/setup.sh"
    echo
    exec docker exec -it "$guard_name" ./openclaw.mjs onboard
  else
    ok "Skipped guard onboarding"
  fi
}

step_configure_worker(){
  local pretty
  pretty=$(title_case_name "$INSTANCE")
  say "Run configure worker"
  say "This is your main assistant — connect your models and Telegram bot here for daily chat."
  echo
  sep
  echo "Recommended worker setup:"
  echo "  • This is your main day-to-day assistant"
  echo "  • Connect your primary model(s) and tools here"
  echo "  • Set up a dedicated Telegram bot for daily chat"
  echo "  • Suggested bot name: ${pretty}-bot"
  echo "  • Use ./openclaw-worker ... for worker-only commands"
  echo
  echo "┌────────────────────────────────────────────────────────┐"
  echo "│ ⚠️  If the onboard script exits early, run this to     │"
  echo "│     launch it again: ./openclaw-worker onboard         │"
  echo "└────────────────────────────────────────────────────────┘"
  echo
  read -r -p "$TIGER Start worker onboarding now? [Y/n]: " go
  if [[ ! "$go" =~ ^[Nn]$ ]]; then
    if ! container_running "$worker_name"; then
      warn "Worker container is not running. Run step 8 first, then try again."
      return
    fi
    echo
    say "Launching worker onboarding in this terminal (not a subprocess). When you're done, run: sudo ./scripts/setup.sh"
    echo
    exec docker exec -it "$worker_name" ./openclaw.mjs onboard
  else
    ok "Skipped worker onboarding"
  fi
}


# True if this instance's "devices list" output shows pairing completed: at least one Paired, no Pending (N) with N>=1
pairing_done_for_output(){
  local out="$1"
  echo "$out" | grep -q 'Paired ([1-9]' && ! echo "$out" | grep -q 'Pending ([1-9]'
}

# Run guard/worker devices list and set PAIRING_COMPLETED=1 only when both have pairing completed.
# Also write/remove a marker file so the main menu can show "✅ Pairing completed" without running docker (status persists across menu redraws and restarts).
# Use docker exec -i (no -t) so we get plain output when run from script; openclaw-guard/openclaw-worker use -it and can fail without a TTY.
PAIRING_STATUS_FILE="${OPENCLAW_STATE_DIR:-/var/lib/openclaw}/.pairing_completed"
update_pairing_status(){
  if ! container_running "$guard_name" || ! container_running "$worker_name"; then
    unset PAIRING_COMPLETED
    rm -f "$PAIRING_STATUS_FILE" 2>/dev/null || true
    return 1
  fi
  local guard_out worker_out
  guard_out=$(docker exec -i "$guard_name" ./openclaw.mjs devices list 2>/dev/null || true)
  worker_out=$(docker exec -i "$worker_name" ./openclaw.mjs devices list 2>/dev/null || true)
  if pairing_done_for_output "$guard_out" && pairing_done_for_output "$worker_out"; then
    export PAIRING_COMPLETED=1
    touch "$PAIRING_STATUS_FILE" 2>/dev/null || true
    return 0
  fi
  unset PAIRING_COMPLETED
  rm -f "$PAIRING_STATUS_FILE" 2>/dev/null || true
  return 1
}

# Extract pending pairing request IDs from "devices list" output (first UUID per line in Pending table).
# Use Python so we don't depend on grep exit codes or awk behaviour across systems.
pending_request_ids(){
  local out="$1"
  python3 - "$out" <<'PY'
import re, sys
text = sys.argv[1] if len(sys.argv) > 1 else ""
uuid_re = re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
pending = False
for line in text.splitlines():
    if re.search(r'[Pp]ending', line):
        pending = True
        continue
    if re.search(r'[Pp]aired', line):
        pending = False
        continue
    if pending:
        m = uuid_re.search(line)
        if m:
            print(m.group(0))
PY
}

# Extract paired count from "devices list" output (Paired (N) line).
paired_count(){
  local out="$1"
  python3 - "$out" <<'PY'
import re, sys
text = sys.argv[1] if len(sys.argv) > 1 else ""
m = re.search(r'[Pp]aired\s*\(\s*(\d+)\s*\)', text)
print(m.group(1) if m else "0")
PY
}

step_auth_tokens(){
  local rot=""
  while true; do
    update_pairing_status || true
    say "Configure Dashboards"
    say "Dashboard URLs, CLI, and pending pairing requests."
    # Ensure each CLI talks to its own gateway (guard→18790, worker→18789); fixes "device token mismatch" / wrong port
    "$STACK_DIR/openclaw-guard" config set gateway.port 18790 >/dev/null 2>&1 || true
    "$STACK_DIR/openclaw-worker" config set gateway.port 18789 >/dev/null 2>&1 || true
    echo "  Docs: https://docs.openclaw.ai/web"
    echo
    # Tokens for dashboard auth (paste into Control UI settings if prompted)
    worker_token=""
    guard_token=""
    if [ -f "$ENV_FILE" ]; then
      worker_token=$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
      guard_token=$(grep -E '^OPENCLAW_GUARD_GATEWAY_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
    fi
    if check_done tailscale; then
      TSDNS=$(tailscale_dns)
      TSDNS=${TSDNS:-unavailable}
      echo "Dashboards (Tailscale HTTPS):"
      if [ -n "$guard_token" ]; then
        echo "  Guard:  https://${TSDNS}:444/#token=${guard_token}"
      else
        echo "  Guard:  https://${TSDNS}:444/  (no token in env — run step 3 or rotate)"
      fi
      if [ -n "$worker_token" ]; then
        echo "  Worker: https://${TSDNS}/#token=${worker_token}"
      else
        echo "  Worker: https://${TSDNS}/  (no token in env — run step 3 or rotate)"
      fi
      echo "  Webtop: https://${TSDNS}:445/"
    else
      echo "Dashboards: not available yet — run option 6 (Tailscale setup)."
      [ -n "$guard_token" ] && echo "  Guard token:  $guard_token"
      [ -n "$worker_token" ] && echo "  Worker token: $worker_token"
    fi
    echo
    # Fetch devices list for pairing status and pending
    guard_devices=""
    worker_devices=""
    if container_running "$guard_name"; then
      guard_devices=$(docker exec -i "$guard_name" ./openclaw.mjs devices list 2>&1 || true)
    fi
    if container_running "$worker_name"; then
      worker_devices=$(docker exec -i "$worker_name" ./openclaw.mjs devices list 2>&1 || true)
    fi
    # DEBUG: set DEBUG_PAIRING=1 when running setup to capture raw devices list output for parsing inspection
    if [ -n "${DEBUG_PAIRING-}" ]; then
      printf '%s' "$guard_devices" > "$STACK_DIR/scripts/.debug-guard-devices.txt" 2>/dev/null || true
      printf '%s' "$worker_devices" > "$STACK_DIR/scripts/.debug-worker-devices.txt" 2>/dev/null || true
    fi
    # Pairing status (paired count per instance)
    guard_paired=$(paired_count "$guard_devices")
    worker_paired=$(paired_count "$worker_devices")
    echo "Pairing status:"
    if [ "${guard_paired:-0}" -gt 0 ] 2>/dev/null; then
      echo "  Guard:  ✅ $guard_paired paired"
    else
      echo "  Guard:  ⚪ No devices paired yet"
    fi
    if [ "${worker_paired:-0}" -gt 0 ] 2>/dev/null; then
      echo "  Worker: ✅ $worker_paired paired"
    else
      echo "  Worker: ⚪ No devices paired yet"
    fi
    if [ "${guard_paired:-0}" -eq 0 ] 2>/dev/null || [ "${worker_paired:-0}" -eq 0 ] 2>/dev/null; then
      echo
      say "Let's set up your dashboards!"
      say "First, open the Guard and Worker dashboards using the links above."
      say "If you see Token mismatch, rotate the keys."
      say "If you see disconnected (1008): pairing required — approve the pairing using the options below."
      echo
    fi
    guard_pending=()
    worker_pending=()
    while IFS= read -r id; do [ -n "$id" ] && guard_pending+=("$id"); done < <(pending_request_ids "$guard_devices")
    while IFS= read -r id; do [ -n "$id" ] && worker_pending+=("$id"); done < <(pending_request_ids "$worker_devices")
    # Build menu: 1 = Rotate, 2 = Refresh, 3..N = Approve (one per pending), 0 = Return
    options=("🔄 Rotate gateway tokens (only use this if you get token mismatch error)" "🔄 Refresh Pairing status")
    option_type=("rotate" "refresh")
    option_id=("" "")
    for id in "${guard_pending[@]}"; do
      short_id="${id:0:8}"
      options+=("🤝 Approve pairing request for Guard — $short_id"); option_type+=("approve_guard"); option_id+=("$id")
    done
    for id in "${worker_pending[@]}"; do
      short_id="${id:0:8}"
      options+=("🤝 Approve pairing request for Worker — $short_id"); option_type+=("approve_worker"); option_id+=("$id")
    done
    num_opts=${#options[@]}
    if [ ${#guard_pending[@]} -gt 0 ] || [ ${#worker_pending[@]} -gt 0 ]; then
      echo "🤝 Pairing Request Detected!"
      echo
    fi
    for i in "${!options[@]}"; do
      printf "  %d. %s\n" $((i+1)) "${options[$i]}"
    done
    echo "  0. Return to main menu"
    echo
    read -r -p "$TIGER Choose [0-$num_opts]: " pick
    pick=${pick:-0}
    if [ "$pick" -eq 0 ] 2>/dev/null; then
      break
    fi
    rot=""
    if [ "$pick" -ge 1 ] 2>/dev/null && [ "$pick" -le "$num_opts" ] 2>/dev/null; then
      idx=$((pick-1))
      case "${option_type[$idx]}" in
        rotate)
          read -r -p "$TIGER Rotate gateway tokens? [y/N] " rot
          case "$rot" in [yY]|[yY][eE][sS]*) rot=yes ;; *) rot="" ;; esac
          ;;
        refresh)
          update_pairing_status || true
          ok "Refreshing pairing status..."
          ;;
        approve_guard)
          docker exec -i "$guard_name" ./openclaw.mjs devices approve "${option_id[$idx]}" 2>&1 && ok "Approved Guard pairing ${option_id[$idx]}" || warn "Approve failed (device list may have changed)"
          ;;
        approve_worker)
          docker exec -i "$worker_name" ./openclaw.mjs devices approve "${option_id[$idx]}" 2>&1 && ok "Approved Worker pairing ${option_id[$idx]}" || warn "Approve failed (device list may have changed)"
          ;;
      esac
    fi
    if [ -n "$rot" ]; then
      if [ ! -f "$ENV_FILE" ]; then
        warn "No env file at $ENV_FILE — run step 3 first."
      else
        sed -i "s#^OPENCLAW_GATEWAY_TOKEN=.*#OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)#" "$ENV_FILE"
        sed -i "s#^OPENCLAW_GUARD_GATEWAY_TOKEN=.*#OPENCLAW_GUARD_GATEWAY_TOKEN=$(openssl rand -hex 24)#" "$ENV_FILE"
        worker_token=$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
        guard_token=$(grep -E '^OPENCLAW_GUARD_GATEWAY_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
        sync_gateway_tokens_to_config "$worker_token" "$guard_token"
        # Recreate (not just restart) so containers pick up new tokens from env file; restart keeps stale env
        if (cd "$STACK_DIR" && docker compose --env-file "$ENV_FILE" -f compose.yml up -d --force-recreate openclaw-gateway openclaw-guard); then
          ok "Tokens rotated and synced to config; guard and worker recreated. Updated URLs below."
          echo
          worker_token=$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
          guard_token=$(grep -E '^OPENCLAW_GUARD_GATEWAY_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
          if check_done tailscale; then
            TSDNS=$(tailscale_dns)
            TSDNS=${TSDNS:-unavailable}
            echo "Dashboards (Tailscale HTTPS):"
            [ -n "$guard_token" ] && echo "  Guard:  https://${TSDNS}:444/#token=${guard_token}" || echo "  Guard:  https://${TSDNS}:444/  (no token in env)"
            [ -n "$worker_token" ] && echo "  Worker: https://${TSDNS}/#token=${worker_token}" || echo "  Worker: https://${TSDNS}/  (no token in env)"
            echo "  Webtop: https://${TSDNS}:445/"
          else
            [ -n "$guard_token" ] && echo "  Guard token:  $guard_token"
            [ -n "$worker_token" ] && echo "  Worker token: $worker_token"
          fi
          echo
        else
          warn "Tokens updated in env and config, but container restart failed."
        fi
      fi
    fi
  done
  update_pairing_status || true
}

step_help_useful_commands(){
  say "Help and useful commands"
  echo
  echo "Roles:"
  echo "  cat /var/lib/openclaw/guard-workspace/ROLE.md"
  echo "  cat /var/lib/openclaw/workspace/ROLE.md"
  echo "  Refresh after git pull or editing core/: sudo ./scripts/sync-workspaces.sh"
  echo
  echo "Devices:"
  echo "  ./openclaw-guard devices list"
  echo "  ./openclaw-guard devices approve <requestId>"
  echo "  ./openclaw-worker devices list"
  echo "  ./openclaw-worker devices approve <requestId>"
  echo
  echo "Pairing:"
  echo "  ./openclaw-guard pairing approve telegram <CODE>"
  echo "  ./openclaw-worker pairing approve telegram <CODE>"
  echo
  echo "Config / tokens:"
  echo "  ./openclaw-guard config get gateway.auth.token"
  echo "  ./openclaw-guard config get channels.telegram.capabilities.inlineButtons"
  echo "  ./openclaw-guard doctor --generate-gateway-token"
  echo "  ./openclaw-worker config get gateway.auth.token"
  echo "  ./openclaw-worker doctor --generate-gateway-token"
  echo
  echo "Run OpenClaw CLI:"
  echo "  ./openclaw-guard"
  echo "  ./openclaw-worker"
}

run_step(){
  local n="$1"
  sep
  case "$n" in
    1) step_preflight ;;
    2) step_volume_root ;;
    3) step_docker ;;
    4) step_env ;;
    5) step_browser_init ;;
    6) step_bitwarden_secrets ;;
    7) step_tailscale ;;
    8) ensure_repo_writable_for_guard; sync_core_workspaces; step_start_guard; ensure_guard_approval_instructions ;;
    9) sync_core_workspaces; step_start_worker ;;
    10) step_start_browser; ensure_browser_profile; ensure_inline_buttons ;;
    11) step_auth_tokens ;;
    12) ensure_guard_bitwarden; sync_core_workspaces; step_configure_guard ;;
    13) sync_core_workspaces; step_configure_worker ;;
    14) step_seed_instructions ;;
    15) step_guard_admin_mode ;;
    16) step_verify ;;
    17) step_help_useful_commands ;;
    *) warn "Unknown step" ;;
  esac
  echo
  read -r -p "$TIGER Press Enter to return to menu..." _
}

menu_once(){
  welcome
  printf "$TIGER Checking status..."
  echo
  echo
  echo "Follow these steps one by one:"
  echo
  printf "  %2d. %-24s | %s\n"  1 "preflight"           "$(step_status 1)"
  printf "  %2d. %-24s | %s\n"  2 "data location (volume)" "$(step_status 2)"
  printf "  %2d. %-24s | %s\n"  3 "docker"              "$(step_status 3)"
  printf "  %2d. %-24s | %s\n"  4 "environment"        "$(step_status 4)"
  printf "  %2d. %-24s | %s\n"  5 "browser init"       "$(step_status 5)"
  printf "  %2d. %-24s | %s\n"  6 "bitwarden"          "$(step_status 6)"
  printf "  %2d. %-24s | %s\n"  7 "tailscale"          "$(step_status 7)"
  printf "  %2d. %-24s | %s\n"  8 "start guard"        "$(step_status 8)"
  printf "  %2d. %-24s | %s\n"  9 "start worker"       "$(step_status 9)"
  printf "  %2d. %-24s | %s\n" 10 "start browser"      "$(step_status 10)"
  printf "  %2d. %-24s | %s\n" 11 "configure Dashboards" "$(step_status 11)"
  printf "  %2d. %-24s | %s\n" 12 "configure guard"    "$(step_status 12)"
  printf "  %2d. %-24s | %s\n" 13 "configure worker"   "$(step_status 13)"
  printf "  %2d. %-24s | %s\n" 14 "seed instructions" "$(step_status 14)"
  printf "  %2d. %-24s | %s\n" 15 "guard admin mode"   "$(step_status 15)"
  printf "  %2d. %-24s | %s\n" 16 "healthcheck"        "$(step_status 16)"
  printf "  %2d. %-24s | %s\n" 17 "help / useful cmds" "$(step_status 17)"
  echo
  read -r -p "$TIGER Select step [1-17] or 0 to exit: " pick
  case "$pick" in
    0) say "Exiting setup wizard. See you soon."; return 1 ;;
    1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17) run_step "$pick" ;;
    *) warn "Invalid choice" ;;
  esac
  return 0
}

need_root
while menu_once; do :; done
