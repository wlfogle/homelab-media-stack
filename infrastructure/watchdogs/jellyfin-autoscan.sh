#!/usr/bin/env bash
# ============================================================
# jellyfin-autoscan.sh
#
# Watches local media directories with inotify and triggers a
# targeted Jellyfin library refresh when new files arrive. Catches
# direct file drops that bypass Sonarr/Radarr (e.g. manual copies,
# rsync, rdt-client output).
#
# Configuration (in /etc/jellyfin-autoscan.env):
#   JELLYFIN_URL=http://192.168.12.231:8096
#   JELLYFIN_API_KEY=<token>
#   WATCH_DIRS=/mnt/media/movies:/mnt/media/tv:/mnt/media/music
#   DEBOUNCE_SECONDS=30
#
# Run via systemd: jellyfin-autoscan.service
# ============================================================
set -Eeuo pipefail

ENV_FILE="${JELLYFIN_AUTOSCAN_ENV:-/etc/jellyfin-autoscan.env}"
if [ -r "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

JELLYFIN_URL="${JELLYFIN_URL:?JELLYFIN_URL must be set in ${ENV_FILE}}"
JELLYFIN_API_KEY="${JELLYFIN_API_KEY:?JELLYFIN_API_KEY must be set in ${ENV_FILE}}"
WATCH_DIRS="${WATCH_DIRS:-/mnt/media/movies:/mnt/media/tv:/mnt/media/music}"
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-30}"

# Split colon-separated list into array, dropping non-existent dirs
IFS=':' read -r -a RAW_DIRS <<<"$WATCH_DIRS"
DIRS=()
for d in "${RAW_DIRS[@]}"; do
  if [ -d "$d" ]; then
    DIRS+=("$d")
  else
    echo "[jellyfin-autoscan] WARN: $d does not exist — skipping" >&2
  fi
done
[ "${#DIRS[@]}" -gt 0 ] || { echo "[jellyfin-autoscan] ERROR: no watch dirs"; exit 1; }

command -v inotifywait >/dev/null 2>&1 || {
  echo "[jellyfin-autoscan] ERROR: inotifywait not installed (apt/nala install inotify-tools)" >&2
  exit 1
}

trigger_refresh() {
  local code
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
    -X POST -H "X-Emby-Token: ${JELLYFIN_API_KEY}" \
    "${JELLYFIN_URL}/Library/Refresh" 2>/dev/null || echo 000)
  if [[ "$code" =~ ^(200|204)$ ]]; then
    echo "[jellyfin-autoscan] $(date -Is) refresh OK (HTTP ${code})"
  else
    echo "[jellyfin-autoscan] $(date -Is) refresh FAILED (HTTP ${code})" >&2
  fi
}

echo "[jellyfin-autoscan] watching: ${DIRS[*]} (debounce ${DEBOUNCE_SECONDS}s, target ${JELLYFIN_URL})"

last_refresh=0
pending=0

# Watch for: file finished writing (close_write), moved into dir
# (moved_to), new file/dir (create), or deletions (delete, moved_from).
# Use --exclude to skip partial files that some clients use.
inotifywait -mrq \
  -e close_write -e moved_to -e create -e delete -e moved_from \
  --exclude '(\.part$|\.!qB$|\.!ut$|/\.tmp/|^\.tmp/|\.swp$)' \
  --format '%T %w%f %e' --timefmt '%s' \
  "${DIRS[@]}" |
while read -r ts path event; do
  now="${ts:-$(date +%s)}"
  pending=1
  # Debounce: collect rapid events, only refresh once per window
  if (( now - last_refresh >= DEBOUNCE_SECONDS )); then
    trigger_refresh
    last_refresh=$now
    pending=0
  fi
done
