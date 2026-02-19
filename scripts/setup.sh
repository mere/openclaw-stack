#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
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
    2) command -v docker >/dev/null 2>&1 && echo "✅ Installed" || echo "⚪ Not installed" ;;
    3) [ -f "$ENV_FILE" ] && echo "✅ Created" || echo "⚪ Not created" ;;
    4) check_done browser_init && echo "✅ CDP scripts installed" || echo "⚪ Not installed" ;;
    5) check_done bitwarden && echo "✅ Configured" || echo "⚪ Not configured" ;;
    6) if check_done tailscale; then tsip=$(tailscale_ip); echo "✅ Running${tsip:+ ($tsip)}"; else echo "⚪ Not running"; fi ;;
    7) container_running "$guard_name" && echo "✅ Currently running" || echo "⚪ Not running" ;;
    8) container_running "$worker_name" && echo "✅ Currently running" || echo "⚪ Not running" ;;
    9) container_running "$browser_name" && echo "✅ Currently running" || echo "⚪ Not running" ;;
    10) configured_label guard ;;
    11) configured_label worker ;;
    12) echo "⚪ Not ready" ;;
    13) echo "Run to verify" ;;
    14) guard_admin_mode_enabled && echo "✅ Enabled" || echo "⚪ Disabled" ;;
    15) check_seed_done && echo "✅ Seeded" || echo "⚪ Not seeded" ;;
    16) echo "—" ;;
    *) echo "—" ;;
  esac
}

# True if both guard and worker ROLE.md contain the seeded core block (CORE:BEGIN marker)
check_seed_done(){
  local gws="${OPENCLAW_GUARD_WORKSPACE_DIR:-/var/lib/openclaw/guard-workspace}"
  local wws="${OPENCLAW_WORKSPACE_DIR:-/var/lib/openclaw/workspace}"
  [ -f "$gws/ROLE.md" ] && grep -q '<!-- CORE:BEGIN -->' "$gws/ROLE.md" || return 1
  [ -f "$wws/ROLE.md" ] && grep -q '<!-- CORE:BEGIN -->' "$wws/ROLE.md" || return 1
  return 0
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
  read -r -s -p "$TIGER BW client secret (it won't be shown): " BW_CLIENTSECRET
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

step_preflight(){
  say "Step 1: Preflight checks"
  say "We verify your host is ready (Ubuntu/Debian, disk space) before proceeding."
  command -v apt-get >/dev/null
  . /etc/os-release
  ok "Host OS: $PRETTY_NAME"
  ok "Disk free on /: $(df -h / | awk 'NR==2 {print $4}')"
}

step_docker(){
  say "Step 2: Docker + Compose"
  say "We use Docker to run the guard, worker and browser as safe, isolated containers."
  if check_done docker; then ok "Docker already installed"; return; fi
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
  say "Step 3: State dirs + environment"
  say "We create directories and an env file so your config and state survive restarts."
  mkdir -p /etc/openclaw /var/lib/openclaw/{state,workspace,browser,guard-state,guard-workspace}
  chown -R 1000:1000 /var/lib/openclaw/state /var/lib/openclaw/workspace /var/lib/openclaw/browser /var/lib/openclaw/guard-state /var/lib/openclaw/guard-workspace
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
  say "Step 4: Browser CDP init scripts"
  say "We install scripts so Chromium starts with remote-debugging on port 9222, proxied to 9223 for automation."
  local browser_dir="/var/lib/openclaw/browser"
  mkdir -p "$browser_dir/custom-cont-init.d"
  install -m 0755 "$STACK_DIR/scripts/webtop-init/20-start-chromium-cdp" "$browser_dir/custom-cont-init.d/20-start-chromium-cdp"
  install -m 0755 "$STACK_DIR/scripts/webtop-init/30-start-socat-cdp-proxy" "$browser_dir/custom-cont-init.d/30-start-socat-cdp-proxy"
  chown -R 1000:1000 "$browser_dir/custom-cont-init.d"
  ok "CDP init scripts installed"
}

step_tailscale(){
  say "Step 5: Tailscale setup (opinionated default)"
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
  read -r -p "$TIGER Install Tailscale now? [y/N]: " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
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
  else
    ok "Skipped Tailscale install"
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


step_auth_tokens(){
  say "Access OpenClaw dashboard and CLI"
  say "Here are your dashboard URLs and CLI commands."
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
    echo "Dashboards: not available yet — run option 7 (Run Tailscale setup)."
    [ -n "$guard_token" ] && echo "  Guard token:  $guard_token"
    [ -n "$worker_token" ] && echo "  Worker token: $worker_token"
  fi
  echo
  echo "CLI:"
  echo "  ./openclaw-guard <command>"
  echo "  ./openclaw-worker <command>"
  echo
  say "Pairing required: if the dashboard shows \"Pairing required\", approve this device from here:"
  echo "  ./openclaw-guard devices list      # Guard dashboard"
  echo "  ./openclaw-guard devices approve <requestId>"
  echo "  ./openclaw-worker devices list     # Worker dashboard"
  echo "  ./openclaw-worker devices approve <requestId>"
  echo "  (If you see \"device token mismatch\", recreate containers to pick up env: sudo ./stop.sh && sudo ./start.sh)"
  echo
  say "If the tokens above don't work, you need to rotate them."
  read -r -p "$TIGER Rotate gateway tokens (e.g. if expired)? [y/N] " rot
  case "$rot" in [yY]|[yY][eE][sS]*) ;; *) rot="" ;; esac
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
        echo "CLI:"
        echo "  ./openclaw-guard <command>"
        echo "  ./openclaw-worker <command>"
      else
        warn "Tokens updated in env and config, but container restart failed."
      fi
    fi
  fi
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
    2) step_docker ;;
    3) step_env ;;
    4) step_browser_init ;;
    5) step_bitwarden_secrets ;;
    6) step_tailscale ;;
    7) ensure_repo_writable_for_guard; sync_core_workspaces; step_start_guard; ensure_guard_approval_instructions ;;
    8) sync_core_workspaces; step_start_worker ;;
    9) step_start_browser; ensure_browser_profile; ensure_inline_buttons ;;
    10) ensure_guard_bitwarden; sync_core_workspaces; step_configure_guard ;;
    11) sync_core_workspaces; step_configure_worker ;;
    12) step_auth_tokens ;;
    13) step_verify ;;
    14) step_guard_admin_mode ;;
    15) step_seed_instructions ;;
    16) step_help_useful_commands ;;
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
  printf "  %2d. %-24s | %s\n"  2 "docker"              "$(step_status 2)"
  printf "  %2d. %-24s | %s\n"  3 "environment"        "$(step_status 3)"
  printf "  %2d. %-24s | %s\n"  4 "browser init"       "$(step_status 4)"
  printf "  %2d. %-24s | %s\n"  5 "bitwarden"          "$(step_status 5)"
  printf "  %2d. %-24s | %s\n"  6 "tailscale"          "$(step_status 6)"
  printf "  %2d. %-24s | %s\n"  7 "start guard"        "$(step_status 7)"
  printf "  %2d. %-24s | %s\n"  8 "start worker"       "$(step_status 8)"
  printf "  %2d. %-24s | %s\n"  9 "start browser"      "$(step_status 9)"
  printf "  %2d. %-24s | %s\n" 10 "configure guard"    "$(step_status 10)"
  printf "  %2d. %-24s | %s\n" 11 "configure worker"   "$(step_status 11)"
  printf "  %2d. %-24s | %s\n" 12 "dashboard URLs"     "$(step_status 12)"
  printf "  %2d. %-24s | %s\n" 13 "healthcheck"        "$(step_status 13)"
  printf "  %2d. %-24s | %s\n" 14 "guard admin mode"   "$(step_status 14)"
  printf "  %2d. %-24s | %s\n" 15 "seed instructions" "$(step_status 15)"
  printf "  %2d. %-24s | %s\n" 16 "help / useful cmds" "$(step_status 16)"
  echo
  read -r -p "$TIGER Select step [1-16] or 0 to exit: " pick
  case "$pick" in
    0) say "Exiting setup wizard. See you soon."; return 1 ;;
    1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16) run_step "$pick" ;;
    *) warn "Invalid choice" ;;
  esac
  return 0
}

need_root
while menu_once; do :; done
