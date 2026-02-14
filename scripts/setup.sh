#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
ENV_FILE=${ENV_FILE:-/etc/openclaw/stack.env}
INSTANCE=${INSTANCE:-chloe}

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

welcome(){
cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                  🐯 OpenClaw Hetzner Setup Wizard               ║
╠══════════════════════════════════════════════════════════════════╣
║ This wizard sets up an end-to-end OpenClaw stack on your VPS:   ║
║  🖥️  Webtop browser (Chromium) for persistent logins             ║
║  👷 Worker OpenClaw instance (daily tasks)                       ║
║  🛡️  Guard OpenClaw instance (privileged operations)              ║
║  🔐 Tailscale for private network access                         ║
║  🔑 Bitwarden env scaffold for secret workflow                   ║
║  🩺 Healthcheck + watchdog validation                            ║
╚══════════════════════════════════════════════════════════════════╝
EOF
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

check_done(){
  local id="$1"
  case "$id" in
    docker) command -v docker >/dev/null 2>&1 ;;
    env) [ -f "$ENV_FILE" ] ;;
    browser_init) [ -f /var/lib/openclaw/browser/custom-cont-init.d/20-start-chromium-cdp ] && [ -f /var/lib/openclaw/browser/custom-cont-init.d/30-start-socat-cdp-proxy ] ;;
    running) container_running "$worker_name" && container_running "$guard_name" ;;
    tailscale) tailscale status >/dev/null 2>&1 ;;
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
  say "Step 5: Tailscale setup"
  say "Why: secure private access instead of exposing services publicly."
  if check_done tailscale; then ok "Tailscale already running"; return; fi
  read -r -p "$TIGER Install Tailscale now? [y/N]: " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    curl -fsSL https://tailscale.com/install.sh | sh >/dev/null
    ok "Tailscale installed"
    say "Run next: tailscale up"
  else
    ok "Skipped Tailscale install"
  fi
}

step_start_guard(){
  say "Start guard service"
  say "Why: guard handles oversight and privileged pathways."
  if container_running "$guard_name"; then ok "Guard already running"; return; fi
  cd "$STACK_DIR"
  docker compose --env-file "$ENV_FILE" -f compose.yml up -d openclaw-guard
  ok "Guard started"
}

step_start_worker(){
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
  say "Start full stack"
  say "Why: starts browser + worker + guard together in one command."
  STACK_DIR="$STACK_DIR" "$STACK_DIR/start.sh" || true
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


step_dashboards(){
  say "Run show dashboards"
  say "Why: quick local links for worker/guard/webtop access."
  sep
  local gw_port guard_port novnc_port
  gw_port=$(grep -E '^GATEWAY_PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
  guard_port=$(grep -E '^GUARD_GATEWAY_PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
  novnc_port=$(grep -E '^NOVNC_PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
  gw_port=${gw_port:-18789}
  guard_port=${guard_port:-18790}
  novnc_port=${novnc_port:-6080}
  echo "Guard dashboard:  http://localhost:${guard_port}"
  echo "Worker dashboard: http://localhost:${gw_port}"
  echo "Webtop (noVNC):   http://localhost:${novnc_port}"
  echo
  echo "CLI helpers from repo root:"
  echo "  ./openclaw-guard <command>   (runs inside guard container)"
  echo "  ./openclaw-worker <command>  (runs inside worker container)"
  echo ""
  echo "Examples:"
  echo "  ./openclaw-guard pairing approve telegram <CODE>"
  echo "  ./openclaw-worker pairing approve telegram <CODE>"
  echo
  say "If remote, use SSH tunnel first (or Tailscale)."
}

run_all(){
  step_preflight
  step_docker
  step_env
  step_browser_init
  step_tailscale
  step_start_all
  step_verify
}

menu_once(){
  welcome
  echo "$TIGER Progress snapshot:"
  check_done docker && ok "Docker installed" || warn "Docker not installed"
  check_done env && ok "Env file exists" || warn "Env file missing"
  check_done browser_init && ok "Browser CDP init installed" || warn "Browser CDP init missing"
  check_done running && ok "Worker + Guard running" || warn "Worker/Guard not both running"
  check_done tailscale && ok "Tailscale running" || warn "Tailscale not running"
  echo
  cat <<EOF
Choose an action:
  1) Run ALL setup steps (recommended)
  2) Run start guard $(status_label "$guard_name")
  3) Run start worker $(status_label "$worker_name")
  4) Run start browser $(status_label "$browser_name")
  5) Run configure guard (openclaw onboard)
  6) Run configure worker (openclaw onboard)
  7) Run Tailscale setup
  8) Run show dashboards
  9) Run healthcheck
  0) Exit
EOF
  echo
  echo "Dashboards: guard http://localhost:18790 | worker http://localhost:18789 | webtop http://localhost:6080"
  echo "Helpers:    ./openclaw-guard pairing approve telegram <CODE>"
  echo "            ./openclaw-worker pairing approve telegram <CODE>"
  read -r -p "$TIGER Select [0-9]: " pick
  case "$pick" in
    1) sep; run_all ;;
    2) sep; step_start_guard ;;
    3) sep; step_start_worker ;;
    4) sep; step_start_browser ;;
    5) sep; step_configure_guard ;;
    6) sep; step_configure_worker ;;
    7) sep; step_tailscale ;;
    8) sep; step_dashboards ;;
    9) sep; step_verify ;;
    0) say "Exiting setup wizard. See you soon."; return 1 ;;
    *) warn "Invalid choice" ;;
  esac
  echo
  read -r -p "$TIGER Press Enter to return to menu..." _
  return 0
}

need_root
while menu_once; do :; done
