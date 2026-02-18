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
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🐯 OpenClaw Setup Wizard"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Setup includes:"
  echo "  🖥️ Webtop browser (Chromium) for persistent logins"
  echo "  🐯 Chloe (worker) OpenClaw instance (daily tasks)"
  echo "  🐕 Op (guard) OpenClaw instance (privileged operations)"
  echo "  🔐 Tailscale for private network access"
  echo "  🔑 Bitwarden env scaffold for secret workflow"
  echo "  🩺 Healthcheck + watchdog validation"
}

need_root(){
  if [ "$EUID" -ne 0 ]; then
    warn "Please run with sudo: sudo ./setup.sh"
    exit 1
  fi
}

container_running(){
  local name="$1"
  docker ps --format '{{.Names}}' | grep -q "^${name}$"
}

status_label(){
  local name="$1"
  if container_running "$name"; then
    echo "(✅ Currently running)"
  else
    echo "(⚪ Not running)"
  fi
}

browser_status_label(){
  local webtop cdp
  if container_running "$browser_name"; then webtop="✅ Webtop running"; else webtop="⚪ Webtop stopped"; fi
  if check_done browser_init; then cdp="✅ CDP installed"; else cdp="⚪ CDP not installed"; fi
  echo "(${webtop}, ${cdp})"
}

simple_status_label(){
  local ok_text="$1"
  local bad_text="$2"
  local check="$3"
  if check_done "$check"; then echo "(✅ ${ok_text})"; else echo "(⚪ ${bad_text})"; fi
}

bitwarden_status_label(){
  if check_done bitwarden; then
    echo "(✅ configured + access ok)"
  else
    echo "(⚪ not configured or access failed)"
  fi
}

configured_label(){
  local kind="$1"
  local file
  if [ "$kind" = "guard" ]; then file="$guard_cfg"; else file="$worker_cfg"; fi
  if [ ! -s "$file" ]; then
    echo "(⚪ Not configured)"
    return
  fi
  if grep -q '"gateway"' "$file" && grep -q '"mode"' "$file"; then
    echo "(✅ Configured)"
  else
    echo "(⚪ Not configured)"
  fi
}

tailscale_ip(){
  tailscale ip -4 2>/dev/null | head -n1 || true
}

tailscale_dns(){
  tailscale status --json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true
}

apply_tailscale_serve(){
  tailscale serve reset >/dev/null 2>&1 || true
  tailscale serve --bg --https=443 http://127.0.0.1:18789 >/dev/null
  tailscale serve --bg --https=444 http://127.0.0.1:18790 >/dev/null
  tailscale serve --bg --https=445 http://127.0.0.1:6080 >/dev/null
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


step_bitwarden_secrets(){
  say "Configure Bitwarden for guard"
  say "This stack uses Bitwarden (https://bitwarden.com) to store credentials safely."
  say "If you don't have one yet, create a free account, then go to Settings → Security → Keys and create an API key."

  local secrets_dir="/var/lib/openclaw/guard-state/secrets"
  local secrets_file="$secrets_dir/bitwarden.env"
  mkdir -p "$secrets_dir"
  chmod 700 "$secrets_dir"

  local cur_server=""
  local cur_email=""
  if [ -f "$secrets_file" ]; then
    cur_server=$(grep '^BW_SERVER=' "$secrets_file" | cut -d= -f2- || true)
    cur_email=$(grep '^BW_EMAIL=' "$secrets_file" | cut -d= -f2- || true)
    ok "Existing bitwarden.env found"
  fi

  say "Did you register on .com or .eu? Enter the server URL accordingly."
  read -r -p "$TIGER BW server URL [${cur_server:-https://vault.bitwarden.eu}]: " BW_SERVER
  BW_SERVER=${BW_SERVER:-${cur_server:-https://vault.bitwarden.eu}}

  read -r -p "$TIGER BW client id: " BW_CLIENTID
  read -r -s -p "$TIGER BW client secret: " BW_CLIENTSECRET
  echo
  read -r -p "$TIGER BW email [${cur_email:-}]: " BW_EMAIL
  BW_EMAIL=${BW_EMAIL:-$cur_email}
  read -r -s -p "$TIGER BW master password: " BW_PASSWORD
  echo

  [ -n "$BW_CLIENTID" ] || { warn "BW client id is required"; return; }
  [ -n "$BW_CLIENTSECRET" ] || { warn "BW client secret is required"; return; }
  [ -n "$BW_EMAIL" ] || { warn "BW email is required"; return; }
  [ -n "$BW_PASSWORD" ] || { warn "BW master password is required"; return; }

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
  say "Why: optionally grant guard full access to /var/lib/openclaw and /etc/openclaw for deep fixes."
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



sync_core_workspaces(){
  "$STACK_DIR/scripts/sync-workspaces.sh" >/dev/null 2>&1 || true
}

ensure_repo_writable_for_guard(){
  say "Ensure repo is writable for guard"
  say "Why: allows guard to patch stack scripts without elevated tool mode."

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
      [ -f /var/lib/openclaw/guard-state/secrets/bitwarden.env ] || return 1
      grep -q '^BW_SERVER=' /var/lib/openclaw/guard-state/secrets/bitwarden.env || return 1
      grep -q '^BW_CLIENTID=' /var/lib/openclaw/guard-state/secrets/bitwarden.env || return 1
      grep -q '^BW_CLIENTSECRET=' /var/lib/openclaw/guard-state/secrets/bitwarden.env || return 1
      grep -q '^BW_EMAIL=' /var/lib/openclaw/guard-state/secrets/bitwarden.env || return 1
      grep -q '^BW_PASSWORD=' /var/lib/openclaw/guard-state/secrets/bitwarden.env || return 1
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
  say "Why: confirm host prerequisites and avoid mid-setup surprises."
  command -v apt-get >/dev/null
  . /etc/os-release
  ok "Host OS: $PRETTY_NAME"
  ok "Disk free on /: $(df -h / | awk 'NR==2 {print $4}')"
}

step_docker(){
  say "Step 2: Docker + Compose"
  say "Why: worker/guard/browser all run as containers."
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
  say "Why: persist config/state across restarts and reboots."
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
}

step_browser_init(){
  say "Step 4: Browser CDP init scripts"
  say "Why: makes Chromium start with remote-debugging + stable proxy (9223)."
  local browser_dir="/var/lib/openclaw/browser"
  mkdir -p "$browser_dir/custom-cont-init.d"
  install -m 0755 "$STACK_DIR/scripts/webtop-init/20-start-chromium-cdp" "$browser_dir/custom-cont-init.d/20-start-chromium-cdp"
  install -m 0755 "$STACK_DIR/scripts/webtop-init/30-start-socat-cdp-proxy" "$browser_dir/custom-cont-init.d/30-start-socat-cdp-proxy"
  chown -R 1000:1000 "$browser_dir/custom-cont-init.d"
  ok "CDP init scripts installed"
}

step_tailscale(){
  say "Step 5: Tailscale setup (opinionated default)"
  say "Why: secure private access instead of exposing services publicly."
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
    say "Run next: tailscale up"
    say "After tailscale up, run option 7 again to configure Tailscale HTTPS endpoints."
  else
    ok "Skipped Tailscale install"
  fi
}

step_start_guard(){
  sync_core_workspaces
  say "Start guard service"
  say "Why: guard handles oversight and privileged pathways."
  if container_running "$guard_name"; then ok "Guard already running"; return; fi
  cd "$STACK_DIR"
  docker compose --env-file "$ENV_FILE" -f compose.yml up -d openclaw-guard
  ok "Guard started"
}

step_start_worker(){
  sync_core_workspaces
  say "Start worker service"
  say "Why: worker is your daily assistant runtime."
  if container_running "$worker_name"; then ok "Worker already running"; return; fi
  cd "$STACK_DIR"
  docker compose --env-file "$ENV_FILE" -f compose.yml up -d openclaw-gateway
  ok "Worker started"
}

step_start_browser(){
  say "Start browser service"
  say "Why: webtop hosts the persistent Chromium profile used for automation."
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
  say "Why: starts browser + worker + guard together in one command."
  STACK_DIR="$STACK_DIR" ENV_FILE="$ENV_FILE" "$STACK_DIR/start.sh"
  ok "Start sequence finished"
}

step_verify(){
  say "Run healthcheck"
  say "Why: confirm stack is truly ready for setup/use."
  STACK_DIR="$STACK_DIR" "$STACK_DIR/healthcheck.sh" || true
  ok "Healthcheck executed"
}

title_case_name(){ local n="$1"; echo "${n^}"; }

step_configure_guard(){
  local pretty
  pretty=$(title_case_name "$INSTANCE")
  "$STACK_DIR/openclaw-guard" config set gateway.port 18790 >/dev/null 2>&1 || true
  "$STACK_DIR/openclaw-guard" config set gateway.bind loopback >/dev/null 2>&1 || true
  say "Run configure guard"
  say "Why: guard is the OpenClaw instance that oversees all operations."
  echo
  sep
  echo "Recommended guard setup:"
  echo "  • Keep it minimal (ideally no extra skills)"
  echo "  • Add a reliable model (e.g., OpenAI Codex auth)"
  echo "  • Set up a dedicated Telegram bot for approvals"
  echo "  • Suggested bot name: ${pretty}-guard-bot"
  echo "  • Use ./openclaw-guard ... for guard-only commands"
  echo
  read -r -p "$TIGER Start guard onboarding now? [Y/n]: " go
  if [[ ! "$go" =~ ^[Nn]$ ]]; then
    docker exec -it "$guard_name" ./openclaw.mjs onboard || true
    ok "Guard setup command finished. If config is already present, this exits quickly — that's normal."
  else
    ok "Skipped guard onboarding"
  fi
}

step_configure_worker(){
  local pretty
  pretty=$(title_case_name "$INSTANCE")
  say "Run configure worker"
  say "Why: this is the AI instance you'll chat to daily and build tasks with."
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
    docker exec -it "$worker_name" ./openclaw.mjs onboard || true
    ok "Worker setup command finished. If config is already present, this exits quickly — that's normal."
  else
    ok "Skipped worker onboarding"
  fi
}


step_auth_tokens(){
  say "Access OpenClaw dashboard and CLI"
  say "Why: this gives you exact dashboard URLs and CLI helpers."
  echo
  if check_done tailscale; then
    TSDNS=$(tailscale_dns)
    TSDNS=${TSDNS:-unavailable}
    echo "Dashboards (Tailscale HTTPS):"
    echo "  Worker: https://${TSDNS}/"
    echo "  Guard:  https://${TSDNS}:444/"
    echo "  Webtop: https://${TSDNS}:445/"
  else
    echo "Dashboards: not available yet — run option 7 (Run Tailscale setup)."
  fi
  echo
  echo "CLI:"
  echo "  ./openclaw-guard <command>"
  echo "  ./openclaw-worker <command>"
  echo

  echo "Useful commands:"
  echo "  cat /var/lib/openclaw/workspace/ROLE.md"
  echo "  cat /var/lib/openclaw/guard-workspace/ROLE.md"
  echo "  ./openclaw-worker devices list"
  echo "  ./openclaw-guard devices list"
  echo "  ./openclaw-worker devices approve <requestId>"
  echo "  ./openclaw-guard devices approve <requestId>"
  echo "  ./openclaw-worker pairing approve telegram <CODE>"
  echo "  ./openclaw-guard pairing approve telegram <CODE>"
  echo "  ./openclaw-worker config get gateway.auth.token"
  echo "  ./openclaw-guard config get gateway.auth.token"
  echo "  ./openclaw-guard config get channels.telegram.capabilities.inlineButtons"
  echo "  ./openclaw-worker doctor --generate-gateway-token"
  echo "  ./openclaw-guard doctor --generate-gateway-token"
  echo "  call \"git status --short\" --reason \"User asked for repo status\" --timeout 30"
  echo "  call \"himalaya envelope list -a icloud -s 20 -o json\" --reason \"User asked for inbox\" --timeout 120"
  echo "  call \"himalaya message read -a icloud 38400\" --reason \"User asked to read email\" --timeout 120"
  echo "  ./scripts/guard-tool-sync.sh"
  echo "  ./scripts/guard-bridge.sh pending"
}

run_all(){
  ensure_repo_writable_for_guard
  step_preflight
  step_docker
  step_env
  step_browser_init
  ensure_browser_profile
  ensure_inline_buttons
  ensure_guard_approval_instructions
  read -r -p "$TIGER Configure Bitwarden secrets now? [y/N]: " bw_ans
  if [[ "$bw_ans" =~ ^[Yy]$ ]]; then
    step_bitwarden_secrets
  fi
  step_tailscale
  step_start_all
  ensure_guard_bitwarden
  step_auth_tokens
  step_verify
}

menu_once(){
  welcome
  cat <<EOF
Choose an action:
  1) Run ALL setup steps (recommended)
  2) Run start guard $(status_label "$guard_name")
  3) Run start worker $(status_label "$worker_name")
  4) Run start browser $(browser_status_label)
  5) Run configure guard (openclaw onboard) $(configured_label guard)
  6) Run configure worker (openclaw onboard) $(configured_label worker)
  7) Run Tailscale setup $(simple_status_label "running" "not running" "tailscale")
  8) Access OpenClaw dashboard and CLI
  9) Configure Bitwarden secrets (guard) $(bitwarden_status_label)
 10) Toggle guard admin mode
 11) Run healthcheck
  0) Exit
EOF
  read -r -p "$TIGER Select [0-11]: " pick
  case "$pick" in
    1) sep; run_all ;;
    2) sep; step_start_guard ;;
    3) sep; step_start_worker ;;
    4) sep; step_start_browser ;;
    5) sep; step_configure_guard ;;
    6) sep; step_configure_worker ;;
    7) sep; step_tailscale ;;
    8) sep; step_auth_tokens ;;
    9) sep; step_bitwarden_secrets ;;
    10) sep; step_guard_admin_mode ;;
    # Keep healthcheck immediately before exit in this menu ordering.
    11) sep; step_verify ;;
    0) say "Exiting setup wizard. See you soon."; return 1 ;;
    *) warn "Invalid choice" ;;
  esac
  echo
  read -r -p "$TIGER Press Enter to return to menu..." _
  return 0
}

need_root
while menu_once; do :; done
