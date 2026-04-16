#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }
kv() { printf "  %-24s %s\n" "$1" "$2"; }

say "RelayTV doctor"
kv "Date (UTC):" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
kv "Kernel:" "$(uname -srmo 2>/dev/null || true)"
kv "Arch:" "$(uname -m)"
kv "User:" "$(id -un) (uid=$(id -u), gid=$(id -g))"
kv "Session type:" "${XDG_SESSION_TYPE:-unknown}"
kv "DISPLAY:" "${DISPLAY:-<unset>}"

# Show GDM Wayland/X11 config hints when present (Ubuntu/Debian GNOME common case)
if command -v dpkg-query >/dev/null 2>&1; then
  if dpkg-query -W -f='${Status}' gdm3 2>/dev/null | grep -q "install ok installed"; then
    if [[ -f /etc/gdm3/custom.conf ]]; then
      wl_line="$(grep -E '^[[:space:]]*WaylandEnable=' /etc/gdm3/custom.conf 2>/dev/null | tail -n 1 || true)"
      say "GDM (X11/Wayland)"
      if [[ -n "$wl_line" ]]; then
        echo "  /etc/gdm3/custom.conf: $wl_line"
      else
        echo "  /etc/gdm3/custom.conf: WaylandEnable not set (default behavior applies)"
      fi
    fi
  fi
fi


SESSION="${XDG_SESSION_TYPE:-unknown}"
if [[ "$SESSION" == "wayland" ]]; then
  say "Overlay status"
  echo "  Wayland session detected — the host X11 overlay fallback is disabled under Wayland."
  echo "  Native Qt overlay/toast remains the primary path."
  echo "  Ubuntu/Debian GNOME: choose \"*on Xorg\" at login (gear icon), or disable Wayland in GDM."
fi


if [[ -f .env ]]; then
  say ".env"
  sed 's/^/  /' .env
else
  say ".env"
  echo "  (missing) — run ./scripts/install.sh"
fi

say "Host devices"
for p in /dev/dri /dev/dri/renderD128 /dev/snd /dev/cec0 /sys/class/drm /dev/tty0; do
  if [[ -e "$p" ]]; then
    kv "$p" "✓ present"
  else
    kv "$p" "- missing"
  fi
done

say "Docker"
if command -v docker >/dev/null 2>&1; then
  kv "docker:" "$(docker --version 2>/dev/null || true)"
else
  kv "docker:" "NOT FOUND"
fi
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    kv "docker compose:" "$(docker compose version 2>/dev/null | head -n 1)"
  else
    kv "docker compose:" "NOT FOUND (use docker-compose v1 or install plugin)"
  fi
fi

say "Compose config sanity"
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  if docker compose config >/dev/null 2>&1; then
    echo "  ✓ docker compose config OK"
  else
    echo "  ✗ docker compose config FAILED"
    docker compose config || true
  fi
else
  echo "  (skipped)"
fi

say "Container status"
if command -v docker >/dev/null 2>&1; then
  docker ps --filter "name=relaytv" --format "  {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
else
  echo "  (docker not installed)"
fi

say "HTTP health checks"
if command -v curl >/dev/null 2>&1; then
  base="${RELAYTV_BASE:-http://127.0.0.1:8787}"
  for ep in /status /ui /x11/overlay; do
    code="$(curl -s -o /dev/null -w "%{http_code}" "$base$ep" || true)"
    kv "$base$ep" "$code"
  done
else
  echo "  curl not installed; skipping HTTP checks"
fi

say "Overlay runtime hints"
if [[ "${XDG_SESSION_TYPE:-}" == "x11" ]]; then
  echo "  X11 session detected."
  echo "  Host X11 overlay fallback is available if explicitly enabled (RELAYTV_X11_OVERLAY=1):"
  echo "    - Host overlay app: python3 app/relaytv_app/overlay_app.py --url http://127.0.0.1:8787/x11/overlay"
  echo "    - In-container overlay requires X11 socket + Xauthority passthrough."
else
  echo "  Not an X11 session. Host X11 overlay fallback will not be active."
fi

echo
echo "Done."
