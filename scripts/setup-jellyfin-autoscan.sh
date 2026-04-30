#!/usr/bin/env bash
# ============================================================
# Jellyfin Autoscan Setup — CT-231 (192.168.12.231:8096)
#
# Configures three layers of automatic library scanning:
#   1. Real-time monitoring (inotify inside Jellyfin) — every library
#   2. Hourly scheduled "Scan Media Library" task — safety net
#   3. (Sonarr/Radarr → Jellyfin Connect notification is handled by
#      scripts/media-pipeline-watchdog.py — see ensure_jellyfin_notification)
#
# A separate host-side inotify watcher for direct /mnt/media drops is
# installed by scripts/install-host-autoscan.sh.
#
# Run on the Proxmox host (Tiamat) as root:
#   bash /opt/homelab-media-stack/scripts/setup-jellyfin-autoscan.sh
#
# Env overrides:
#   JELLYFIN_CTID=231          # Jellyfin LXC container ID
#   SCAN_INTERVAL_HOURS=1      # scheduled scan period (1..24)
# ============================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/phase7-common.sh"

JELLYFIN_CTID="${JELLYFIN_CTID:-231}"
SCAN_INTERVAL_HOURS="${SCAN_INTERVAL_HOURS:-1}"

p7_step "Jellyfin Autoscan → CT-${JELLYFIN_CTID}"
p7_require_pve

# ── 0. Sanity: container running and Jellyfin reachable ─────────────────────
if ! p7_ct_exists "$JELLYFIN_CTID"; then
  p7_error "CT-${JELLYFIN_CTID} does not exist. Deploy Jellyfin first."
  exit 1
fi
p7_ct_start_and_wait "$JELLYFIN_CTID"

JF_IP=$(pct exec "$JELLYFIN_CTID" -- hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$JF_IP" ] && JF_IP="192.168.12.231"
JF_URL="http://${JF_IP}:8096"

p7_info "Verifying Jellyfin health at ${JF_URL} ..."
if ! p7_http_ok "${JF_URL}/health" 200 30 >/dev/null; then
  p7_error "Jellyfin not healthy at ${JF_URL}. Check 'pct exec ${JELLYFIN_CTID} -- systemctl status jellyfin'."
  exit 1
fi
p7_ok "Jellyfin reachable."

# ── 1. Mint a dedicated Autoscan API key (idempotent) ───────────────────────
p7_info "Resolving Autoscan API key ..."
API_KEY=$(pct exec "$JELLYFIN_CTID" -- bash -c \
  "sqlite3 /var/lib/jellyfin/data/jellyfin.db \"SELECT AccessToken FROM ApiKeys WHERE Name='Autoscan' LIMIT 1\"" \
  2>/dev/null | tr -d '\r\n' || true)

if [ -z "$API_KEY" ]; then
  # Bootstrap from any existing key to mint a new one via API
  ADMIN_KEY=$(pct exec "$JELLYFIN_CTID" -- bash -c \
    "sqlite3 /var/lib/jellyfin/data/jellyfin.db \"SELECT AccessToken FROM ApiKeys LIMIT 1\"" \
    2>/dev/null | tr -d '\r\n' || true)
  if [ -z "$ADMIN_KEY" ]; then
    p7_error "Jellyfin has no API keys to bootstrap from. Create one in Dashboard → API Keys, then re-run."
    exit 1
  fi
  p7_info "Creating new 'Autoscan' API key via Jellyfin API ..."
  pct exec "$JELLYFIN_CTID" -- bash -c \
    "curl -fsS -X POST -H 'X-Emby-Token: ${ADMIN_KEY}' 'http://127.0.0.1:8096/Auth/Keys?App=Autoscan' >/dev/null" \
    2>/dev/null || true
  API_KEY=$(pct exec "$JELLYFIN_CTID" -- bash -c \
    "sqlite3 /var/lib/jellyfin/data/jellyfin.db \"SELECT AccessToken FROM ApiKeys WHERE Name='Autoscan' ORDER BY DateCreated DESC LIMIT 1\"" \
    2>/dev/null | tr -d '\r\n' || true)
  [ -z "$API_KEY" ] && { p7_error "Failed to create Autoscan API key."; exit 1; }
  p7_ok "Autoscan API key created."
else
  p7_ok "Reusing existing 'Autoscan' API key."
fi

# ── 2. Enable real-time monitoring on every library ─────────────────────────
# Library options live in /var/lib/jellyfin/config/libraries/<lib>/options.xml
# We patch <EnableRealtimeMonitor>true</EnableRealtimeMonitor> in each, then
# restart Jellyfin to pick up the change.
p7_info "Enabling real-time monitoring on all libraries ..."
PATCH_RESULT=$(pct exec "$JELLYFIN_CTID" -- bash -s <<'PATCH'
set -Eeuo pipefail
LIB_DIR="/var/lib/jellyfin/config/libraries"
if [ ! -d "$LIB_DIR" ]; then
  echo "no-libs"
  exit 0
fi
shopt -s nullglob
changed=0
total=0
for f in "$LIB_DIR"/*/options.xml; do
  total=$((total+1))
  if grep -q '<EnableRealtimeMonitor>' "$f"; then
    if grep -q '<EnableRealtimeMonitor>false</EnableRealtimeMonitor>' "$f"; then
      sed -i 's|<EnableRealtimeMonitor>false</EnableRealtimeMonitor>|<EnableRealtimeMonitor>true</EnableRealtimeMonitor>|' "$f"
      changed=$((changed+1))
    fi
  else
    # Insert before the closing </LibraryOptions> tag
    sed -i 's|</LibraryOptions>|  <EnableRealtimeMonitor>true</EnableRealtimeMonitor>\n</LibraryOptions>|' "$f"
    changed=$((changed+1))
  fi
done
echo "total=${total} changed=${changed}"
PATCH
)
p7_ok "Library options: ${PATCH_RESULT}"

# ── 3. Restart Jellyfin so option.xml edits take effect ─────────────────────
if [[ "$PATCH_RESULT" == *"changed=0"* ]] || [[ "$PATCH_RESULT" == "no-libs" ]]; then
  p7_info "No library option changes — skipping restart."
else
  p7_info "Restarting Jellyfin to apply real-time monitoring ..."
  pct exec "$JELLYFIN_CTID" -- systemctl restart jellyfin
  # Wait for it to come back
  for _ in $(seq 1 60); do
    code=$(curl -fsS --max-time 2 -o /dev/null -w '%{http_code}' "${JF_URL}/health" 2>/dev/null || echo 000)
    [ "$code" = "200" ] && break
    sleep 2
  done
  p7_ok "Jellyfin back up."
fi

# ── 4. Set the scheduled "Scan Media Library" task to every N hours ────────
p7_info "Configuring hourly scheduled library scan (every ${SCAN_INTERVAL_HOURS}h) ..."

# .NET ticks: 1 tick = 100 ns. 1 hour = 3.6e10 ticks.
INTERVAL_TICKS=$(( SCAN_INTERVAL_HOURS * 36000000000 ))

# Find the RefreshLibrary task. Its Key is "RefreshLibrary".
TASK_ID=$(curl -fsS -H "X-Emby-Token: ${API_KEY}" \
  "${JF_URL}/ScheduledTasks" 2>/dev/null \
  | python3 -c "
import sys, json
tasks = json.load(sys.stdin)
for t in tasks:
    if t.get('Key') == 'RefreshLibrary':
        print(t['Id']); break
" || true)

if [ -z "$TASK_ID" ]; then
  p7_warn "Could not locate 'RefreshLibrary' scheduled task — skipping scheduled-scan setup."
else
  TRIGGER_BODY=$(printf '[{"Type":"IntervalTrigger","IntervalTicks":%s}]' "$INTERVAL_TICKS")
  HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' \
    -X POST -H "X-Emby-Token: ${API_KEY}" -H "Content-Type: application/json" \
    --data "${TRIGGER_BODY}" \
    "${JF_URL}/ScheduledTasks/${TASK_ID}/Triggers" 2>/dev/null || echo 000)
  if [[ "$HTTP_CODE" =~ ^(200|204)$ ]]; then
    p7_ok "Scheduled library scan set to run every ${SCAN_INTERVAL_HOURS}h (HTTP ${HTTP_CODE})."
  else
    p7_warn "Failed to set scheduled-scan trigger (HTTP ${HTTP_CODE})."
  fi
fi

# ── 5. Surface the API key for downstream installers ───────────────────────
KEY_FILE="/etc/jellyfin-autoscan.env"
umask 077
cat > "$KEY_FILE" <<ENV
# Autogenerated by scripts/setup-jellyfin-autoscan.sh
JELLYFIN_URL=${JF_URL}
JELLYFIN_API_KEY=${API_KEY}
ENV
chmod 600 "$KEY_FILE"
p7_ok "Wrote ${KEY_FILE} (mode 0600). Used by scripts/install-host-autoscan.sh."

# ── 6. Trigger one scan now so any pre-existing files appear ───────────────
p7_info "Triggering one immediate library refresh ..."
curl -fsS -X POST -H "X-Emby-Token: ${API_KEY}" "${JF_URL}/Library/Refresh" >/dev/null \
  && p7_ok "Initial refresh queued." \
  || p7_warn "Initial refresh request failed (non-fatal)."

p7_step "Done."
echo
echo "Next step (host-side inotify watcher for manual file drops):"
echo "  bash ${SCRIPT_DIR}/install-host-autoscan.sh"
echo
echo "The Sonarr/Radarr → Jellyfin Connect webhook is auto-created by the"
echo "media-pipeline-watchdog (every 5 min). Force a run with:"
echo "  systemctl start media-pipeline-watchdog.service"
