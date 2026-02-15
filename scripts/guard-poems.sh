#!/usr/bin/env bash
set -euo pipefail
ACTION=${1:-}
POEMS_FILE=/home/node/.openclaw/bridge/poem-of-the-day.txt
mkdir -p /home/node/.openclaw/bridge

today_poem() {
  cat <<'EOF'
Clouds stitch silver over midnight rails,
A quiet server hums through patient night;
We ship small truths in logs and careful trails,
And wake to find the morning wired bright.
EOF
}

case "$ACTION" in
  poems.read)
    if [ -f "$POEMS_FILE" ]; then
      poem=$(cat "$POEMS_FILE")
    else
      poem=$(today_poem)
    fi
    python3 - <<PY
import json
print(json.dumps({"ok": True, "poem": '''$poem'''}, ensure_ascii=False))
PY
    ;;
  poems.write)
    # policy should reject before execution; keep defensive reject here too
    echo '{"ok":false,"error":"policy_rejected_write"}'
    exit 4
    ;;
  poems.delete)
    rm -f "$POEMS_FILE"
    echo '{"ok":true,"deleted":true}'
    ;;
  *)
    echo '{"ok":false,"error":"unsupported_poem_action"}'
    exit 1
    ;;
esac
