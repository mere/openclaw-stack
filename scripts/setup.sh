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

welcome(){
cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                  🐯 OpenClaw Hetzner Setup Wizard               ║
╠══════════════════════════════════════════════════════════════════╣
║ This wizard sets up an end-to-end OpenClaw stack on your VPS:   ║
║  • Webtop browser (Chromium) for persistent logins              ║
║  • Worker OpenClaw instance (daily tasks)                       ║
║  • Guard OpenClaw instance (privileged operations)              ║
║  • Optional Tailscale (private network access)                  ║
║  • Optional Bitwarden env scaffold (secret workflow)            ║
║  • Healthcheck + watchdog validation                            ║
╚══════════════════════════════════════════════════════════════════╝
EOF
}

need_root(){
  if [ "$EUID" -ne 0 ]; then
    warn "Please run with sudo: sudo ./setup.sh"
    exit 1
  fi
}

check_done(){
  local id="$1"
  case "$id" in
    docker) command -v docker >/dev/null 2>&1 ;;
    env) [ -f "$ENV_FILE" ] ;;
    browser_init) [ -f /var/lib/openclaw/browser/custom-cont-init.d/20-start-chromium-cdp ] && [ -f /var/lib/openclaw/browser/custom-cont-init.d/30-start-socat-cdp-proxy ] ;;
    running) docker ps --format "{{.Names}}" | grep -q "^${INSTANCE}-openclaw-gateway$" && docker ps --format "{{.Names}}" | grep -q "^${INSTANCE}-openclaw-guard$" ;;
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

step_optional_tailscale(){
  say "Step 5: Optional Tailscale"
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

step_start(){
  say "Step 6: Start stack"
  say "Why: launch browser + worker + guard services."
  STACK_DIR="$STACK_DIR" "$STACK_DIR/start.sh" || true
  ok "Start sequence finished"
}

step_verify(){
  say "Step 7: Verify health"
  say "Why: confirm stack is truly ready for setup/use."
  STACK_DIR="$STACK_DIR" "$STACK_DIR/healthcheck.sh" || true
  ok "Healthcheck executed"
}

title_case_name() {
  local n="$1"
  echo "${n^}"
}

step_configure_guard(){
  local pretty
  pretty=$(title_case_name "$INSTANCE")
  say "Configure Guard"
  say "Why: guard is the control-plane instance that oversees privileged operations."
  echo
  echo "Recommended guard setup:"
  echo "  • Keep it minimal: no extra skills unless absolutely needed"
  echo "  • Add one reliable model (e.g., OpenAI Codex auth)"
  echo "  • Use a separate Telegram bot for guard approvals"
  echo "  • Suggested bot name: ${pretty}-guard-bot"
  echo
  read -r -p "$TIGER Start guard onboarding now? [Y/n]: " go
  if [[ ! "$go" =~ ^[Nn]$ ]]; then
    docker exec -it "${INSTANCE}-openclaw-guard" ./openclaw.mjs setup
  else
    ok "Skipped guard onboarding"
  fi
}

step_configure_worker(){
  local pretty
  pretty=$(title_case_name "$INSTANCE")
  say "Configure Worker"
  say "Why: worker is your daily AI companion for chats, tasks, and automations."
  echo
  echo "Recommended worker setup:"
  echo "  • This is the main assistant you'll talk to every day"
  echo "  • Connect your primary model(s) and tools here"
  echo "  • Use a separate Telegram bot for daily interaction"
  echo "  • Suggested bot name: ${pretty}-bot"
  echo
  read -r -p "$TIGER Start worker onboarding now? [Y/n]: " go
  if [[ ! "$go" =~ ^[Nn]$ ]]; then
    docker exec -it "${INSTANCE}-openclaw-gateway" ./openclaw.mjs setup
  else
    ok "Skipped worker onboarding"
  fi
}

run_all(){
  step_preflight
  step_docker
  step_env
  step_browser_init
  step_optional_tailscale
  step_start
  step_verify
}

menu(){
  welcome
  echo "$TIGER Progress snapshot:"
  check_done docker && ok "Docker installed" || warn "Docker not installed"
  check_done env && ok "Env file exists" || warn "Env file missing"
  check_done browser_init && ok "Browser CDP init installed" || warn "Browser CDP init missing"
  check_done running && ok "Worker + Guard running" || warn "Worker/Guard not running"
  check_done tailscale && ok "Tailscale running" || warn "Tailscale not running"
  echo
  cat <<EOF
Choose an action:
  1) Run ALL (recommended)
  2) Start stack only
  3) Healthcheck only
  4) Tailscale step only
  5) Configure guard (openclaw setup)
  6) Configure worker (openclaw setup)
  0) Exit
EOF
  read -r -p "$TIGER Select [0-6]: " pick
  case "$pick" in
    1) run_all ;;
    2) step_start ;;
    3) step_verify ;;
    4) step_optional_tailscale ;;
    5) step_configure_guard ;;
    6) step_configure_worker ;;
    0) say "Exiting setup wizard. See you soon." ;;
    *) warn "Invalid choice"; exit 1 ;;
  esac
}

need_root
menu
