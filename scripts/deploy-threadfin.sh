#!/usr/bin/env bash
# ============================================================
# Phase 7 — Threadfin (CT-234 @ 192.168.12.234:34400/web)
#
# M3U / XMLTV proxy for Jellyfin Live TV. Native Go binary.
#
# Run on Proxmox host (Tiamat):
#   bash /opt/homelab-media-stack/scripts/deploy-threadfin.sh
#
# Env:
#   FORCE_RECREATE=1   destroy CT-234 and rebuild
# ============================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/phase7-common.sh"

CTID=234
HOSTNAME=threadfin
IP=192.168.12.234

p7_step "Threadfin → CT-${CTID} @ ${IP}:34400"
p7_require_pve
[ "${FORCE_RECREATE:-0}" = "1" ] && p7_ct_destroy_if_exists "$CTID"

p7_ct_create "$CTID" "$HOSTNAME" "$IP" 1 1024 4
p7_ct_start_and_wait "$CTID"

p7_info "Installing ffmpeg + vlc + deps ..."
p7_ct_run "$CTID" <<'BASH'
apt-get update -qq
apt-get install -y --no-install-recommends -qq \
  curl ca-certificates ffmpeg vlc-bin vlc-plugin-base tzdata
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo America/New_York > /etc/timezone
BASH

p7_info "Fetching latest Threadfin binary ..."
p7_ct_run "$CTID" <<'BASH'
set -Eeuo pipefail
mkdir -p /opt/threadfin
URL=$(curl -fsSL https://api.github.com/repos/Threadfin/Threadfin/releases/latest \
  | grep -oE '"browser_download_url":\s*"[^"]+Threadfin_linux_amd64"' \
  | head -n1 | cut -d'"' -f4)
[ -n "$URL" ] || { echo "Threadfin asset not found"; exit 1; }
curl -fsSL "$URL" -o /opt/threadfin/threadfin
chmod +x /opt/threadfin/threadfin
/opt/threadfin/threadfin --version || /opt/threadfin/threadfin -h 2>&1 | head -20
BASH

p7_info "Writing systemd unit ..."
p7_ct_write "$CTID" /etc/systemd/system/threadfin.service 0644 root:root <<'UNIT'
[Unit]
Description=Threadfin - M3U Proxy for Jellyfin Live TV
After=syslog.target network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/threadfin
ExecStart=/opt/threadfin/threadfin
TimeoutStopSec=20
KillMode=process
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

p7_ct_run "$CTID" <<'BASH'
systemctl daemon-reload
systemctl enable --now threadfin
sleep 4
systemctl is-active threadfin
BASH

CODE=$(p7_http_ok "http://${IP}:34400/web" 200 30 || true)
if [[ "$CODE" =~ ^(200|302|301)$ ]]; then
  p7_ok "Threadfin HTTP ${CODE} at http://${IP}:34400/web — complete setup wizard + load your M3U."
else
  p7_error "Threadfin did not come up. pct exec ${CTID} -- journalctl -u threadfin -n 50"
  exit 1
fi
