#!/usr/bin/env bash
# ============================================================
# install-host-autoscan.sh
#
# Installs the jellyfin-autoscan inotify watcher on the host that
# owns /mnt/media (Tiamat / Proxmox). Triggers a Jellyfin library
# refresh whenever files appear, move, or get deleted in the watch
# directories — covering manual drops that bypass Sonarr/Radarr.
#
# Prereq: scripts/setup-jellyfin-autoscan.sh has already run and
# produced /etc/jellyfin-autoscan.env on this host. (If you run this
# from a different host, copy that file over first.)
#
# Run as root on the host that mounts /mnt/media:
#   bash /opt/homelab-media-stack/scripts/install-host-autoscan.sh
#
# Env overrides:
#   WATCH_DIRS=/mnt/media/movies:/mnt/media/tv:/mnt/media/music
#   DEBOUNCE_SECONDS=30
#   INOTIFY_MAX_USER_WATCHES=524288
# ============================================================
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_SRC="${REPO_DIR}/infrastructure/watchdogs/jellyfin-autoscan.sh"
UNIT_SRC="${REPO_DIR}/infrastructure/watchdogs/jellyfin-autoscan.service"
SCRIPT_DST="/usr/local/bin/jellyfin-autoscan.sh"
UNIT_DST="/etc/systemd/system/jellyfin-autoscan.service"
ENV_FILE="/etc/jellyfin-autoscan.env"

WATCH_DIRS_DEFAULT="/mnt/media/movies:/mnt/media/tv:/mnt/media/music"
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-30}"
INOTIFY_MAX_USER_WATCHES="${INOTIFY_MAX_USER_WATCHES:-524288}"

info()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()   { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

[ "$(id -u)" -eq 0 ] || { err "Must run as root."; exit 1; }
[ -r "$SCRIPT_SRC" ]  || { err "Missing source: $SCRIPT_SRC"; exit 1; }
[ -r "$UNIT_SRC" ]    || { err "Missing source: $UNIT_SRC"; exit 1; }

# ── 1. Install inotify-tools (prefer nala) ──────────────────────────────────
if ! command -v inotifywait >/dev/null 2>&1; then
  info "Installing inotify-tools ..."
  if command -v nala >/dev/null 2>&1; then
    nala install -y inotify-tools
  elif command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends inotify-tools
  else
    err "Neither nala nor apt-get found — install inotify-tools manually."
    exit 1
  fi
  ok "inotify-tools installed."
else
  ok "inotify-tools already present."
fi

# ── 2. Bump inotify watch limit (large libraries hit 8192 default fast) ─────
SYSCTL_FILE="/etc/sysctl.d/99-jellyfin-inotify.conf"
if [ ! -f "$SYSCTL_FILE" ] || ! grep -q "^fs.inotify.max_user_watches=${INOTIFY_MAX_USER_WATCHES}$" "$SYSCTL_FILE"; then
  info "Setting fs.inotify.max_user_watches=${INOTIFY_MAX_USER_WATCHES} ..."
  printf 'fs.inotify.max_user_watches=%s\nfs.inotify.max_user_instances=1024\n' \
    "$INOTIFY_MAX_USER_WATCHES" > "$SYSCTL_FILE"
  sysctl --system >/dev/null
  ok "inotify limits applied."
else
  ok "inotify limits already set."
fi

# ── 3. Ensure /etc/jellyfin-autoscan.env exists ─────────────────────────────
if [ ! -r "$ENV_FILE" ]; then
  warn "${ENV_FILE} not found — run scripts/setup-jellyfin-autoscan.sh first to mint the API key."
  warn "You can also create it manually:"
  cat <<EOF >&2
  cat > ${ENV_FILE} <<'EOFENV'
  JELLYFIN_URL=http://192.168.12.231:8096
  JELLYFIN_API_KEY=<paste from Jellyfin Dashboard → API Keys>
  WATCH_DIRS=${WATCH_DIRS_DEFAULT}
  DEBOUNCE_SECONDS=${DEBOUNCE_SECONDS}
  EOFENV
  chmod 600 ${ENV_FILE}
EOF
  exit 1
fi

# Append WATCH_DIRS / DEBOUNCE_SECONDS if missing (idempotent)
if ! grep -q '^WATCH_DIRS=' "$ENV_FILE"; then
  echo "WATCH_DIRS=${WATCH_DIRS_DEFAULT}" >> "$ENV_FILE"
fi
if ! grep -q '^DEBOUNCE_SECONDS=' "$ENV_FILE"; then
  echo "DEBOUNCE_SECONDS=${DEBOUNCE_SECONDS}" >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"

# ── 4. Install script + unit ────────────────────────────────────────────────
info "Installing ${SCRIPT_DST} ..."
install -m 0755 "$SCRIPT_SRC" "$SCRIPT_DST"

info "Installing ${UNIT_DST} ..."
install -m 0644 "$UNIT_SRC" "$UNIT_DST"

systemctl daemon-reload
systemctl enable --now jellyfin-autoscan.service

sleep 2
if systemctl is-active --quiet jellyfin-autoscan.service; then
  ok "jellyfin-autoscan.service is running."
  info "Tail logs: journalctl -u jellyfin-autoscan -f"
else
  err "jellyfin-autoscan.service failed to start. Check: journalctl -u jellyfin-autoscan -n 50"
  exit 1
fi
