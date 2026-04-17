#!/usr/bin/env bash
# ============================================================
# Phase 7 — Decluttarr (CT-216 @ 192.168.12.216, no web UI)
#
# Watches Sonarr / Radarr / Lidarr / Readarr queues and removes
# stalled, failed, or blocked downloads. No UI; logs to journald.
#
# Pulls API keys at runtime from CT-214/215/217/218.
#
# Run on Proxmox host (Tiamat):
#   bash /opt/homelab-media-stack/scripts/deploy-decluttarr.sh
#
# Env:
#   FORCE_RECREATE=1   destroy CT-216 and rebuild
# ============================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/phase7-common.sh"

CTID=216
HOSTNAME=decluttarr
IP=192.168.12.216

p7_step "Decluttarr → CT-${CTID} @ ${IP} (no UI)"
p7_require_pve
[ "${FORCE_RECREATE:-0}" = "1" ] && p7_ct_destroy_if_exists "$CTID"

p7_ct_create "$CTID" "$HOSTNAME" "$IP" 1 512 2
p7_ct_start_and_wait "$CTID"

p7_info "Discovering *arr API keys ..."
SONARR_KEY=$(p7_arr_key 214 sonarr || true)
RADARR_KEY=$(p7_arr_key 215 radarr || true)
READARR_KEY=$(p7_arr_key 217 readarr || true)
LIDARR_KEY=$(p7_arr_key 218 lidarr || true)
[ -n "$SONARR_KEY" ] || { p7_error "Sonarr key missing"; exit 1; }
[ -n "$RADARR_KEY" ] || { p7_error "Radarr key missing"; exit 1; }
# Readarr / Lidarr are optional but recommended
[ -z "$READARR_KEY" ] && p7_warn "Readarr key not found; Readarr section will be disabled."
[ -z "$LIDARR_KEY" ]  && p7_warn "Lidarr key not found; Lidarr section will be disabled."

p7_info "Installing Python + venv + git ..."
p7_ct_run "$CTID" <<'BASH'
apt-get update -qq
apt-get install -y --no-install-recommends -qq \
  python3 python3-venv python3-pip git ca-certificates curl tzdata
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo America/New_York > /etc/timezone
BASH

p7_info "Cloning decluttarr latest ..."
p7_ct_run "$CTID" <<'BASH'
set -Eeuo pipefail
rm -rf /opt/decluttarr
git clone --depth 1 https://github.com/ManiMatter/decluttarr.git /opt/decluttarr
cd /opt/decluttarr
python3 -m venv venv
./venv/bin/pip install --quiet --upgrade pip
# Upstream ships requirements under docker/; fall back to pyproject if missing
if [ -f docker/requirements.txt ]; then
  ./venv/bin/pip install --quiet -r docker/requirements.txt
else
  ./venv/bin/pip install --quiet .
fi
BASH

p7_info "Writing /etc/default/decluttarr (env) ..."
# Build optional Readarr/Lidarr sections conditionally
READARR_BLOCK=""
LIDARR_BLOCK=""
if [ -n "$READARR_KEY" ]; then
READARR_BLOCK="READARR_URL=http://192.168.12.217:8787
READARR_KEY=${READARR_KEY}"
fi
if [ -n "$LIDARR_KEY" ]; then
LIDARR_BLOCK="LIDARR_URL=http://192.168.12.218:8686
LIDARR_KEY=${LIDARR_KEY}"
fi

p7_ct_write "$CTID" /etc/default/decluttarr 0600 root:root <<ENV
# Managed by scripts/deploy-decluttarr.sh — see
# https://github.com/ManiMatter/decluttarr#configuration
LOG_LEVEL=INFO
TEST_RUN=False
SSL_VERIFICATION=False

# Run loop interval and thresholds
REMOVE_TIMER=10
REMOVE_FAILED=True
REMOVE_FAILED_IMPORTS=True
REMOVE_METADATA_MISSING=True
REMOVE_MISSING_FILES=True
REMOVE_ORPHANS=True
REMOVE_SLOW=False
REMOVE_STALLED=True
REMOVE_UNMONITORED=True
RUN_PERIODIC_RESCANS={"SONARR":  {"MISSING": true, "CUTOFF_UNMET": true, "MAX_CONCURRENT_SCANS": 3, "MIN_DAYS_BEFORE_RESCAN": 7}, "RADARR":  {"MISSING": true, "CUTOFF_UNMET": true, "MAX_CONCURRENT_SCANS": 3, "MIN_DAYS_BEFORE_RESCAN": 7}}
PERMITTED_ATTEMPTS=3
NO_STALLED_REMOVAL_QBIT_TAG=Don't Kill
MIN_DOWNLOAD_SPEED=100
IGNORED_DOWNLOAD_CLIENTS=

# Sonarr
SONARR_URL=http://192.168.12.214:8989
SONARR_KEY=${SONARR_KEY}

# Radarr (note: .225 per README, CT-215)
RADARR_URL=http://192.168.12.225:7878
RADARR_KEY=${RADARR_KEY}

${READARR_BLOCK}
${LIDARR_BLOCK}

# qBittorrent
QBITTORRENT_URL=http://192.168.12.212:8080
QBITTORRENT_USERNAME=admin
QBITTORRENT_PASSWORD=adminadmin
ENV

p7_info "Writing systemd unit ..."
p7_ct_write "$CTID" /etc/systemd/system/decluttarr.service 0644 root:root <<'UNIT'
[Unit]
Description=Decluttarr - *arr queue janitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/decluttarr
EnvironmentFile=/etc/default/decluttarr
ExecStart=/opt/decluttarr/venv/bin/python /opt/decluttarr/main.py
Restart=on-failure
RestartSec=15
User=root

[Install]
WantedBy=multi-user.target
UNIT

p7_info "Starting decluttarr.service ..."
p7_ct_run "$CTID" <<'BASH'
systemctl daemon-reload
systemctl enable --now decluttarr
sleep 3
systemctl is-active decluttarr
journalctl -u decluttarr -n 10 --no-pager || true
BASH

p7_ok "Decluttarr running in CT-${CTID}. Watch with:  pct exec ${CTID} -- journalctl -u decluttarr -f"
