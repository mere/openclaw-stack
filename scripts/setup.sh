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
  echo "┃   🔑 Bitwarden (passwordless: no secrets in files)         ┃"
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
  # Match exact name or Compose-prefixed name (e.g. project_op-and-chloe-openclaw-guard)
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "^${name}$|_${name}$"
}

# Return the actual running container name for docker exec (Compose may prefix e.g. 31f2873beb14_op-and-chloe-openclaw-guard).
resolve_container_name(){
  local logical="$1"
  command -v docker >/dev/null 2>&1 || return 1
  docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^${logical}$|_${logical}$" | head -1
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
    15) guard_admin_mode_enabled && echo "⚠️ Enabled (full VPS access—disable when not needed)" || echo "⚪ Disabled" ;;
    16) echo "" ;;
    17) echo "" ;;
    *) echo "—" ;;
  esac
}

# True if both workspaces have .seed_hash matching current core/ (ROLE.md + skills) content
# (seeded = hash of core/<profile> equals workspace/.seed_hash written at last sync)
check_seed_done(){
  local gws="${OPENCLAW_GUARD_WORKSPACE_DIR:-/var/lib/openclaw/guard-workspace}"
  local wws="${OPENCLAW_WORKSPACE_DIR:-/var/lib/openclaw/workspace}"
  local want want_g want_w have_g have_w
  want_g=$(python3 "$STACK_DIR/scripts/seed-hash.py" get "$STACK_DIR" guard 2>/dev/null)
  want_w=$(python3 "$STACK_DIR/scripts/seed-hash.py" get "$STACK_DIR" worker 2>/dev/null)
  have_g=$(cat "$gws/.seed_hash" 2>/dev/null | tr -d '\n')
  have_w=$(cat "$wws/.seed_hash" 2>/dev/null | tr -d '\n')
  [ -n "$want_g" ] && [ "$want_g" = "$have_g" ] || return 1
  [ -n "$want_w" ] && [ "$want_w" = "$have_w" ] || return 1
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
  # Prefer dynamic CDP URL from running browser container so Chloe's browser tool stays correct
  if container_running "$browser_name"; then
    if STACK_DIR="$STACK_DIR" ENV_FILE="$ENV_FILE" "$STACK_DIR/scripts/update-webtop-cdp-url.sh" 2>/dev/null; then
      return 0
    fi
  fi
  # Fallback: set profile with CDP URL from env or default (when browser not running yet)
  local bip="172.31.0.10"
  if [ -f "$ENV_FILE" ]; then
    bip=$(grep -E '^BROWSER_IPV4=' "$ENV_FILE" | cut -d= -f2- | tr -d '"' | head -1)
    [ -z "$bip" ] && bip="172.31.0.10"
  fi
  BIP="$bip" python3 - <<'PY2'
import json, os, pathlib
bip = os.environ.get("BIP", "172.31.0.10")
worker=pathlib.Path('/var/lib/openclaw/state/openclaw.json')
guard=pathlib.Path('/var/lib/openclaw/guard-state/openclaw.json')
if worker.exists() and worker.stat().st_size>0:
    d=json.loads(worker.read_text())
    b=d.setdefault('browser',{})
    b['enabled']=True
    b['defaultProfile']='vps-chromium'
    prof=b.setdefault('profiles',{})
    p=prof.setdefault('vps-chromium',{})
    p['cdpUrl']=f'http://{bip}:9223'
    p.setdefault('color','#00AAFF')
    worker.write_text(json.dumps(d,indent=2)+"\n")
if guard.exists() and guard.stat().st_size>0:
    d=json.loads(guard.read_text())
    d.setdefault('browser',{})['enabled']=False
    guard.write_text(json.dumps(d,indent=2)+"\n")
PY2
  chown 1000:1000 /var/lib/openclaw/state/openclaw.json /var/lib/openclaw/guard-state/openclaw.json 2>/dev/null || true
}


# Bitwarden CLI data dir: shared between host (setup) and guard container (same path under mount).
BW_CLI_DATA_DIR_HOST="/var/lib/openclaw/guard-state/bitwarden-cli"
BW_CLI_DATA_DIR_GUARD="/home/node/.openclaw/bitwarden-cli"

bitwarden_env_hash(){
  local f="$1"
  [ -f "$f" ] || return 1
  sha256sum < "$f" 2>/dev/null | cut -d' ' -f1 || openssl dgst -sha256 -r 2>/dev/null < "$f" | cut -d' ' -f1
}

verify_bitwarden_credentials(){
  local secrets_file="$1"
  local secrets_dir="$2"
  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi
  local state_dir
  state_dir="$(dirname "$secrets_dir")"
  # Use same guard-state mount as guard so CLI data dir is visible; only BW_SERVER is in env.
  if docker run --rm \
    -v "$state_dir:/home/node/.openclaw:rw" \
    --env-file "$secrets_file" \
    -e BITWARDENCLI_APPDATA_DIR="$BW_CLI_DATA_DIR_GUARD" \
    node:20-alpine sh -c '
      npm install -g @bitwarden/cli >/dev/null 2>&1 &&
      bw status 2>/dev/null | grep -qv "unauthenticated"
    ' >/dev/null 2>&1; then
    local h
    h=$(bitwarden_env_hash "$secrets_file")
    [ -n "$h" ] && echo "$h" > "$secrets_dir/.bw_verified" && chmod 600 "$secrets_dir/.bw_verified" 2>/dev/null
    return 0
  fi
  return 1
}

# Check if Bitwarden is unlocked in the guard container. Returns 0 if unlocked, 1 if guard not running, 2 if locked.
check_bitwarden_unlocked_in_guard(){
  local guard_actual
  guard_actual=$(resolve_container_name "$guard_name" 2>/dev/null)
  guard_actual=${guard_actual:-$guard_name}
  if ! container_running "$guard_name"; then
    return 1
  fi
  ensure_guard_bitwarden >/dev/null 2>&1 || true
  if docker exec "$guard_actual" sh -lc '
    export BITWARDENCLI_APPDATA_DIR=/home/node/.openclaw/bitwarden-cli
    . /home/node/.openclaw/secrets/bitwarden.env
    [ -f /home/node/.openclaw/secrets/bw-session ] && export BW_SESSION=$(cat /home/node/.openclaw/secrets/bw-session)
    bw config server "$BW_SERVER" >/dev/null 2>&1 || true
    s=$(bw status 2>/dev/null || true)
    echo "$s" | grep -q "\"status\":\"unlocked\""
  ' 2>/dev/null; then
    return 0
  fi
  return 2
}

# Unlock the vault and persist the session key so the guard can use bw in other processes.
# Password is read once and passed via a temp file that is removed immediately; only the session key is written to guard-state.
BW_SESSION_FILE_NAME="bw-session"

run_bitwarden_unlock_interactive(){
  local state_dir="$1"
  local secrets_dir="$state_dir/secrets"
  local session_file="$secrets_dir/$BW_SESSION_FILE_NAME"
  say "Unlock the vault. Enter your master password (used only for this unlock; it is not stored)."
  # Use a global name so the RETURN trap can still rm the file after the function returns (locals are gone then).
  _bw_tmp_pw=$(mktemp)
  chmod 600 "$_bw_tmp_pw"
  trap 'rm -f "$_bw_tmp_pw"' RETURN
  read -rs -p "$TIGER Master password: " pw
  echo
  printf '%s' "$pw" > "$_bw_tmp_pw"
  unset pw

  local session_key
  if container_running "$guard_name"; then
    local guard_actual
    guard_actual=$(resolve_container_name "$guard_name" 2>/dev/null)
    guard_actual=${guard_actual:-$guard_name}
    ensure_guard_bitwarden >/dev/null 2>&1 || true
    docker cp "$_bw_tmp_pw" "$guard_actual:/tmp/bw-pw" 2>/dev/null || true
    session_key=$(docker exec "$guard_actual" sh -lc '
      export BITWARDENCLI_APPDATA_DIR=/home/node/.openclaw/bitwarden-cli
      . /home/node/.openclaw/secrets/bitwarden.env
      bw config server "$BW_SERVER" >/dev/null 2>&1 || true
      bw unlock --raw --passwordfile /tmp/bw-pw
    ' 2>/dev/null) || true
    docker exec "$guard_actual" rm -f /tmp/bw-pw 2>/dev/null || true
  else
    session_key=$(docker run -i --rm \
      -v "$state_dir:/home/node/.openclaw:rw" \
      -v "$_bw_tmp_pw:/tmp/bw-pw:ro" \
      -e BITWARDENCLI_APPDATA_DIR="$BW_CLI_DATA_DIR_GUARD" \
      node:20-alpine sh -c 'npm install -g @bitwarden/cli >/dev/null 2>&1 && . /home/node/.openclaw/secrets/bitwarden.env && bw config server "$BW_SERVER" && bw unlock --raw --passwordfile /tmp/bw-pw' 2>/dev/null) || true
  fi

  if [ -n "$session_key" ]; then
    echo -n "$session_key" > "$session_file"
    chmod 600 "$session_file"
    chown 1000:1000 "$session_file" 2>/dev/null || true
    ok "Session key saved so the guard can use Bitwarden (re-run this step if the vault is locked later)."
  else
    warn "Unlock failed or session could not be captured; try again or run step 6 again."
  fi
}

step_bitwarden_secrets(){
  local secrets_dir="/var/lib/openclaw/guard-state/secrets"
  local secrets_file="$secrets_dir/bitwarden.env"
  local bw_data_dir="$BW_CLI_DATA_DIR_HOST"
  mkdir -p "$secrets_dir" "$bw_data_dir"
  chmod 700 "$secrets_dir" "$bw_data_dir"
  chown 1000:1000 "$secrets_dir" "$bw_data_dir" 2>/dev/null || true

  if [ -f "$secrets_file" ]; then
    say "Configure Bitwarden for guard"
    say "Verifying existing login state..."
    if verify_bitwarden_credentials "$secrets_file" "$secrets_dir"; then
      ok "Bitwarden logged in"
      if check_bitwarden_unlocked_in_guard; then
        ok "Bitwarden unlocked"
        return
      fi
      run_bitwarden_unlock_interactive "$(dirname "$secrets_dir")"
      if [ -f "$secrets_dir/$BW_SESSION_FILE_NAME" ]; then
        chown -R 1000:1000 "$bw_data_dir" 2>/dev/null || true
        ok "Bitwarden unlocked"
      fi
      return
    fi
    warn "Existing login missing or expired — you will log in again below"
    echo
  fi

  say "Configure Bitwarden for guard (no master password stored)"
  say "We use Bitwarden to share credentials safely with OpenClaw. You log in and unlock in this step. Only BW_SERVER and the session key from unlock are saved on the host; your master password is never written to disk."
  say "Create a free account on https://vault.bitwarden.com or https://vault.bitwarden.eu — whichever is closer to you."

  local cur_server=""
  local default_choice="1"
  if [ -f "$secrets_file" ]; then
    cur_server=$(grep '^BW_SERVER=' "$secrets_file" | cut -d= -f2- || true)
    ok "Existing bitwarden.env found"
    [[ "$cur_server" == *".com"* ]] && default_choice="1" || default_choice="2"
  fi

  echo "  1) I use https://vault.bitwarden.com"
  echo "  2) I use https://vault.bitwarden.eu"
  read -r -p "$TIGER BW server [1 or 2]: " ans
  ans=${ans:-$default_choice}
  if [[ "$ans" == "1" ]]; then
    BW_SERVER="https://vault.bitwarden.com"
  else
    BW_SERVER="https://vault.bitwarden.eu"
  fi

  rm -f "$secrets_dir/.bw_verified"
  cat > "$secrets_file" <<EOF
BW_SERVER=$BW_SERVER
EOF
  chmod 600 "$secrets_file"
  chown 1000:1000 "$secrets_file" 2>/dev/null || true
  ok "Saved $secrets_file (server URL only; no passwords or credentials stored)"

  say "Log in and unlock here (email, master password, 2FA if enabled). Your password is not stored; only the session key is saved so the guard can use Bitwarden."
  do_bw_login(){
    export BITWARDENCLI_APPDATA_DIR="$bw_data_dir"
    bw logout 2>/dev/null || true
    bw config server "$BW_SERVER" && bw login
  }
  if command -v bw >/dev/null 2>&1; then
    if ! do_bw_login; then
      warn "Bitwarden login failed or was cancelled"
      return
    fi
    chown -R 1000:1000 "$bw_data_dir" 2>/dev/null || true
  elif command -v docker >/dev/null 2>&1; then
    local state_dir
    state_dir="$(dirname "$secrets_dir")"
    if ! docker run -it --rm \
      -v "$state_dir:/home/node/.openclaw:rw" \
      -e BITWARDENCLI_APPDATA_DIR="$BW_CLI_DATA_DIR_GUARD" \
      -e BW_SERVER="$BW_SERVER" \
      node:20-alpine sh -c 'npm install -g @bitwarden/cli >/dev/null 2>&1 && bw logout 2>/dev/null || true && bw config server "$BW_SERVER" && bw login'; then
      warn "Bitwarden login failed or was cancelled"
      return
    fi
    chown -R 1000:1000 "$bw_data_dir" 2>/dev/null || true
  else
    warn "Install Bitwarden CLI (npm install -g @bitwarden/cli) or Docker, then re-run this step"
    return
  fi

  say "Verifying login..."
  if verify_bitwarden_credentials "$secrets_file" "$secrets_dir"; then
    ok "Bitwarden logged in"
    say "Unlock the vault so the guard can read secrets."
    run_bitwarden_unlock_interactive "$(dirname "$secrets_dir")"
    chown -R 1000:1000 "$bw_data_dir" 2>/dev/null || true
    ok "Bitwarden unlocked"
  else
    if command -v docker >/dev/null 2>&1; then
      warn "Verification failed — ensure guard-state is at the default path or run this step again"
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
  local guard_actual; guard_actual=$(resolve_container_name "$guard_name" 2>/dev/null); guard_actual=${guard_actual:-$guard_name}
  if docker exec "$guard_actual" sh -lc 'command -v bw >/dev/null 2>&1'; then
    ok "Guard Bitwarden CLI available"
    return
  fi
  say "Installing Bitwarden CLI in guard..."
  docker exec "$guard_actual" sh -lc 'npm i -g @bitwarden/cli --prefix /home/node/.openclaw/npm-global >/dev/null 2>&1 || true'
  if docker exec "$guard_actual" sh -lc 'command -v bw >/dev/null 2>&1'; then
    ok "Guard Bitwarden CLI installed"
  else
    warn "Guard Bitwarden CLI install failed (can retry manually)."
  fi
}



guard_admin_mode_enabled(){
  grep -q '/var/lib/openclaw:/mnt/openclaw-data' "$STACK_DIR/compose.yml"
}

# SSH key for Op to connect back to host (Admin Mode). Stored in guard-state, mounted into container when admin mode on.
ensure_guard_ssh_to_host(){
  local ssh_dir="/var/lib/openclaw/guard-state/ssh"
  local key_file="$ssh_dir/id_ed25519"
  local auth_keys="/root/.ssh/authorized_keys"
  mkdir -p "$ssh_dir"
  if [ ! -f "$key_file" ]; then
    ssh-keygen -t ed25519 -f "$key_file" -N "" -C "openclaw-guard-admin" -q
    ok "Generated SSH key for Op→host at $ssh_dir"
  fi
  chown -R 1000:1000 "$ssh_dir"
  chmod 700 "$ssh_dir"
  [ -f "$key_file" ] && chmod 600 "$key_file"
  mkdir -p /root/.ssh
  touch "$auth_keys"
  chmod 600 "$auth_keys"
  if ! grep -q "openclaw-guard-admin" "$auth_keys" 2>/dev/null; then
    cat "${key_file}.pub" >> "$auth_keys"
    ok "Added Op SSH public key to $auth_keys (Op can ssh root@localhost when Admin Mode is on)"
  fi
}

set_guard_admin_mode(){
  local mode="$1"  # on|off
  local c="$STACK_DIR/compose.yml"
  if [ "$mode" = "on" ]; then
    ensure_guard_ssh_to_host
    if ! grep -q '/var/lib/openclaw:/mnt/openclaw-data' "$c"; then
      sed -i '/OPENCLAW_GUARD_WORKSPACE_DIR.*workspace/a\
      - /var/lib/openclaw:/mnt/openclaw-data\
      - /etc/openclaw:/mnt/etc-openclaw\
      - /var/lib/openclaw/guard-state/ssh:/home/node/.ssh:ro' "$c"
    elif ! grep -q '/var/lib/openclaw/guard-state/ssh:/home/node/.ssh' "$c"; then
      sed -i '\# /etc/openclaw:/mnt/etc-openclaw#a\
      - /var/lib/openclaw/guard-state/ssh:/home/node/.ssh:ro' "$c"
    fi
    ok "Guard admin mode enabled (full host data/config mounted; Op can SSH to host as root@localhost)"
  else
    sed -i '\# /var/lib/openclaw:/mnt/openclaw-data#d' "$c"
    sed -i '\# /etc/openclaw:/mnt/etc-openclaw#d' "$c"
    sed -i '\# /var/lib/openclaw/guard-state/ssh:/home/node/.ssh#d' "$c"
    ok "Guard admin mode disabled (minimal mounts; Op cannot SSH to host)"
  fi
  cd "$STACK_DIR"
  docker compose --env-file "$ENV_FILE" -f compose.yml up -d --force-recreate openclaw-guard >/dev/null || true
}

step_guard_admin_mode(){
  say "Guard admin mode"
  say "When enabled: guard can access /var/lib/openclaw and /etc/openclaw, and Op can SSH back to this host (e.g. ssh root@localhost) for shell access."
  if guard_admin_mode_enabled; then
    warn "Admin mode is ON. Op has full access to this VPS (data, config, SSH). Enable only temporarily when absolutely necessary."
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
      y|Y)
        warn "Admin mode gives Op full access to this VPS. Enable only temporarily when absolutely necessary."
        set_guard_admin_mode on
        ;;
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

# Ensure repo files are writable by the runtime user (avoid root-owned drift)
fix_repo_ownership(){
  local repo="${STACK_DIR:-/opt/op-and-chloe}"
  chown -R 1000:1000 "$repo" 2>/dev/null || true
}

ensure_repo_writable_for_guard(){
  say "Ensure repo is writable for guard"
  say "We set permissions so the guard can edit stack scripts when needed."

  fix_repo_ownership

  # Avoid git ownership/filemode noise
  git -C "$STACK_DIR" config core.fileMode false 2>/dev/null || true
  git config --global --add safe.directory "$STACK_DIR" 2>/dev/null || true

  # Also inside guard container (path is /opt/op-and-chloe)
  if container_running "$guard_name"; then
    guard_actual=$(resolve_container_name "$guard_name" 2>/dev/null); guard_actual=${guard_actual:-$guard_name}
    docker exec "$guard_actual" sh -lc 'git config --global --add safe.directory /opt/op-and-chloe >/dev/null 2>&1 || true'
  fi

  ok "Repo permissions/safe.directory configured"
}

ensure_bridge_dirs(){
  mkdir -p /var/lib/openclaw/bridge/inbox /var/lib/openclaw/bridge/outbox /var/lib/openclaw/bridge/audit
  mkdir -p /var/lib/openclaw/guard-state/bridge
  chown -R 1000:1000 /var/lib/openclaw/bridge /var/lib/openclaw/guard-state/bridge 2>/dev/null || true
}

ensure_worker_bridge_client(){
  local scripts_dir="$STACK_DIR/scripts"
  mkdir -p "$scripts_dir"

  # Keep worker bridge entrypoints deterministic and executable.
  cat > "$scripts_dir/call" <<'EOF'
#!/usr/bin/env bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$SCRIPT_DIR/worker-bridge.sh" call "$@"
EOF

  cat > "$scripts_dir/catalog" <<'EOF'
#!/usr/bin/env bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$SCRIPT_DIR/worker-bridge.sh" catalog
EOF

  chmod 0755 "$scripts_dir/call" "$scripts_dir/catalog" "$scripts_dir/worker-bridge.sh" 2>/dev/null || true
  chown 1000:1000 "$scripts_dir/call" "$scripts_dir/catalog" "$scripts_dir/worker-bridge.sh" 2>/dev/null || true
}

ensure_worker_bridge_mounts(){
  local c="$STACK_DIR/compose.yml"
  local needle='/var/lib/openclaw/bridge/outbox:/var/lib/openclaw/bridge/outbox:rw'
  if grep -q "$needle" "$c"; then
    return
  fi

  python3 - "$c" <<'PY2'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
old = "      - /var/lib/openclaw/bridge/inbox:/var/lib/openclaw/bridge/inbox:rw\n"
new = old + "      - /var/lib/openclaw/bridge/outbox:/var/lib/openclaw/bridge/outbox:rw\n"
if old not in s:
    raise SystemExit("compose patch failed: inbox mount anchor not found")
p.write_text(s.replace(old, new, 1))
PY2
}


ensure_stack_repo_alias(){
  # Keep /opt/op-and-chloe available for scripts that rely on canonical path.
  local canonical="/opt/op-and-chloe"
  mkdir -p /opt
  if [ -L "$canonical" ]; then
    local cur
    cur=$(readlink -f "$canonical" 2>/dev/null || true)
    if [ "$cur" != "$STACK_DIR" ]; then
      ln -snf "$STACK_DIR" "$canonical"
    fi
  elif [ -e "$canonical" ]; then
    warn "$canonical exists and is not a symlink; leaving as-is"
  else
    ln -snf "$STACK_DIR" "$canonical"
  fi
}

ensure_guard_bridge_service(){
  # Install and enable the guard bridge timer/service with current STACK_DIR path.
  install -m 0644 "$STACK_DIR/systemd/openclaw-guard-bridge.timer" /etc/systemd/system/openclaw-guard-bridge.timer
  sed "s#/opt/op-and-chloe#$STACK_DIR#g" "$STACK_DIR/systemd/openclaw-guard-bridge.service" > /etc/systemd/system/openclaw-guard-bridge.service
  systemctl daemon-reload
  systemctl enable --now openclaw-guard-bridge.timer >/dev/null 2>&1 || true
}


ensure_m365_bridge_policy(){
  local cp="/var/lib/openclaw/guard-state/bridge/command-policy.json"
  mkdir -p /var/lib/openclaw/guard-state/bridge
  [ -f "$cp" ] || echo '{"rules":[]}' > "$cp"
  python3 - "$cp" <<'PY2'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1])
try:
    d=json.loads(p.read_text())
except Exception:
    d={"rules":[]}
rules=d.setdefault("rules",[])

def upsert(rule_id, pattern, decision):
    for r in rules:
        if r.get("id")==rule_id:
            r["pattern"]=pattern; r["decision"]=decision; return
    rules.append({"id":rule_id,"pattern":pattern,"decision":decision})

upsert("m365-auth-login", r"^python3\s+/opt/op-and-chloe/scripts/guard-m365\.py\s+auth\s+login\b", "ask")
upsert("m365-auth-status", r"^python3\s+/opt/op-and-chloe/scripts/guard-m365\.py\s+auth\s+status\b", "approved")
upsert("m365-mail-list", r"^python3\s+/opt/op-and-chloe/scripts/guard-m365\.py\s+mail\s+list\b", "approved")
upsert("m365-mail-read", r"^python3\s+/opt/op-and-chloe/scripts/guard-m365\.py\s+mail\s+read\b", "approved")
upsert("m365-calendar-events", r"^python3\s+/opt/op-and-chloe/scripts/guard-m365\.py\s+calendar\s+events\b", "approved")
upsert("m365-calendar-list", r"^python3\s+/opt/op-and-chloe/scripts/guard-m365\.py\s+calendar\s+list\b", "approved")

p.write_text(json.dumps(d, indent=2)+"\n")
PY2
  chown 1000:1000 "$cp" 2>/dev/null || true
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
      local want_h got_h
      want_h=$(bitwarden_env_hash "$bw_env" 2>/dev/null)
      got_h=$(cat "$bw_verified" 2>/dev/null)
      if ! container_running "$guard_name"; then
        [ -f "$bw_verified" ] && [ -n "$want_h" ] && [ "$want_h" = "$got_h" ] && return 0
        return 1
      fi
      guard_actual=$(resolve_container_name "$guard_name" 2>/dev/null)
      guard_actual=${guard_actual:-$guard_name}
      docker exec "$guard_actual" sh -lc '
        set -e
        command -v bw >/dev/null 2>&1
        . /home/node/.openclaw/secrets/bitwarden.env
        [ -n "$BW_SERVER" ]
        export BITWARDENCLI_APPDATA_DIR="/home/node/.openclaw/bitwarden-cli"
        [ -f /home/node/.openclaw/secrets/bw-session ] && export BW_SESSION=$(cat /home/node/.openclaw/secrets/bw-session)
        bw config server "$BW_SERVER" >/dev/null 2>&1
        bw status >/tmp/bw-status.json 2>/dev/null || exit 1
        grep -q '"status":"unauthenticated"' /tmp/bw-status.json && exit 1
        grep -q '"status":"unlocked"' /tmp/bw-status.json || exit 1
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
  ensure_stack_repo_alias
  ensure_guard_bridge_service
  say "Start guard service"
  say "The guard oversees privileged operations and approves Chloe's requests for credentials and tools."
  if container_running "$guard_name"; then ok "Guard already running"; return; fi
  cd "$STACK_DIR"
  docker compose --env-file "$ENV_FILE" -f compose.yml up -d openclaw-guard
  ok "Guard started"
}

step_start_worker(){
  sync_core_workspaces
  ensure_bridge_dirs
  ensure_worker_bridge_client
  ensure_worker_bridge_mounts
  ensure_m365_bridge_policy
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
  ensure_stack_repo_alias
  ensure_guard_bridge_service
  ensure_repo_writable_for_guard
  ensure_bridge_dirs
  ensure_worker_bridge_client
  ensure_worker_bridge_mounts
  ensure_m365_bridge_policy
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
    guard_actual=$(resolve_container_name "$guard_name" 2>/dev/null); guard_actual=${guard_actual:-$guard_name}
    echo
    say "Launching guard onboarding in this terminal (not a subprocess). When you're done, run: sudo ./scripts/setup.sh"
    echo
    exec docker exec -it "$guard_actual" ./openclaw.mjs onboard
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
    worker_actual=$(resolve_container_name "$worker_name" 2>/dev/null); worker_actual=${worker_actual:-$worker_name}
    echo
    say "Launching worker onboarding in this terminal (not a subprocess). When you're done, run: sudo ./scripts/setup.sh"
    echo
    exec docker exec -it "$worker_actual" ./openclaw.mjs onboard
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
  local guard_actual worker_actual guard_out worker_out
  guard_actual=$(resolve_container_name "$guard_name" 2>/dev/null) || guard_actual="$guard_name"
  worker_actual=$(resolve_container_name "$worker_name" 2>/dev/null) || worker_actual="$worker_name"
  guard_out=$(docker exec -i "$guard_actual" ./openclaw.mjs devices list 2>/dev/null || true)
  worker_out=$(docker exec -i "$worker_actual" ./openclaw.mjs devices list 2>/dev/null || true)
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
    # Fetch devices list for pairing status and pending (use resolved names for Compose-prefixed containers)
    guard_devices=""
    worker_devices=""
    guard_actual=$(resolve_container_name "$guard_name" 2>/dev/null); guard_actual=${guard_actual:-$guard_name}
    worker_actual=$(resolve_container_name "$worker_name" 2>/dev/null); worker_actual=${worker_actual:-$worker_name}
    if container_running "$guard_name"; then
      guard_devices=$(docker exec -i "$guard_actual" ./openclaw.mjs devices list 2>&1 || true)
    fi
    if container_running "$worker_name"; then
      worker_devices=$(docker exec -i "$worker_actual" ./openclaw.mjs devices list 2>&1 || true)
    fi
    # DEBUG: set DEBUG_PAIRING=1 when running setup to capture raw devices list output for parsing inspection
    if [ -n "${DEBUG_PAIRING-}" ]; then
      printf '%s' "$guard_devices" > "$STACK_DIR/scripts/.debug-guard-devices.txt" 2>/dev/null || true
      printf '%s' "$worker_devices" > "$STACK_DIR/scripts/.debug-worker-devices.txt" 2>/dev/null || true
    fi
    # Pairing status (paired count per instance). If CLI returns token mismatch, we can't read the list.
    guard_paired=$(paired_count "$guard_devices")
    worker_paired=$(paired_count "$worker_devices")
    guard_token_err=0; worker_token_err=0
    echo "$guard_devices" | grep -qi "token mismatch\|unauthorized.*device" && guard_token_err=1
    echo "$worker_devices" | grep -qi "token mismatch\|unauthorized.*device" && worker_token_err=1
    echo "Pairing status:"
    if [ "${guard_paired:-0}" -gt 0 ] 2>/dev/null; then
      echo "  Guard:  ✅ $guard_paired paired"
    elif [ "$guard_token_err" -eq 1 ]; then
      echo "  Guard:  ⚠️ Token mismatch — rotate keys (option 1) to connect"
    else
      echo "  Guard:  ⚪ No devices paired yet"
    fi
    if [ "${worker_paired:-0}" -gt 0 ] 2>/dev/null; then
      echo "  Worker: ✅ $worker_paired paired"
    elif [ "$worker_token_err" -eq 1 ]; then
      echo "  Worker: ⚠️ Token mismatch — rotate keys (option 1) to connect"
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
          docker exec -i "$guard_actual" ./openclaw.mjs devices approve "${option_id[$idx]}" 2>&1 && ok "Approved Guard pairing ${option_id[$idx]}" || warn "Approve failed (device list may have changed)"
          ;;
        approve_worker)
          docker exec -i "$worker_actual" ./openclaw.mjs devices approve "${option_id[$idx]}" 2>&1 && ok "Approved Worker pairing ${option_id[$idx]}" || warn "Approve failed (device list may have changed)"
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
  fix_repo_ownership
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
