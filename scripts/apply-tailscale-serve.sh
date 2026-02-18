#!/usr/bin/env bash
# Apply Tailscale serve config: Worker (443), Guard (444), Webtop (445)
# Run this after tailscale up and whenever the stack starts.
set -euo pipefail

tailscale serve reset >/dev/null 2>&1 || true
tailscale serve --yes --bg --https=443 http://127.0.0.1:18789
tailscale serve --yes --bg --https=444 http://127.0.0.1:18790
tailscale serve --yes --bg --https=445 http://127.0.0.1:6080
