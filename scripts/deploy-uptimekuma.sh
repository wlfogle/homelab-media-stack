#!/usr/bin/env bash
# ============================================================
# Phase 7 — Uptime Kuma (CT-248 @ 192.168.12.248:3001)
#
# Self-hosted uptime / health monitoring. Replaces the homegrown
# scripts/stack-watchdog.sh.
#
# Run on Proxmox host (Tiamat):
#   bash /opt/homelab-media-stack/scripts/deploy-uptimekuma.sh
#
# Env:
#   FORCE_RECREATE=1   destroy CT-248 and rebuild
# ============================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/phase7-common.sh"

CTID=248
HOSTNAME=uptime-kuma
IP=192.168.12.248

p7_step "Uptime Kuma → CT-${CTID} @ ${IP}:3001"
p7_require_pve
[ "${FORCE_RECREATE:-0}" = "1" ] && p7_ct_destroy_if_exists "$CTID"

p7_ct_create "$CTID" "$HOSTNAME" "$IP" 1 1024 4
p7_ct_start_and_wait "$CTID"

p7_info "Installing Node 22, git, chromium for real-browser monitors ..."
p7_ct_run "$CTID" <<'BASH'
apt-get update -qq
apt-get install -y --no-install-recommends -qq \
  curl ca-certificates gnupg git build-essential chromium tzdata
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo America/New_York > /etc/timezone
if ! command -v node >/dev/null 2>&1 || ! node --version | grep -q '^v22'; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y --no-install-recommends -qq nodejs
fi
node --version
BASH

p7_info "Fetching Uptime Kuma latest tarball ..."
p7_ct_run "$CTID" <<'BASH'
set -Eeuo pipefail
rm -rf /opt/uptime-kuma
mkdir -p /opt/uptime-kuma
TARBALL=$(curl -fsSL https://api.github.com/repos/louislam/uptime-kuma/releases/latest \
  | grep -oE '"tarball_url":\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
[ -n "$TARBALL" ] || { echo "Cannot find uptime-kuma tarball"; exit 1; }
curl -fsSL "$TARBALL" -o /tmp/uk.tar.gz
tar -xzf /tmp/uk.tar.gz -C /opt/uptime-kuma --strip-components=1
rm -f /tmp/uk.tar.gz

ln -sf /usr/bin/chromium /opt/uptime-kuma/chromium || true
cd /opt/uptime-kuma
npm ci --omit=dev 2>&1 | tail -n 20
npm run download-dist 2>&1 | tail -n 20
BASH

p7_info "Writing systemd unit ..."
p7_ct_write "$CTID" /etc/systemd/system/uptime-kuma.service 0644 root:root <<'UNIT'
[Unit]
Description=Uptime Kuma
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
User=root
WorkingDirectory=/opt/uptime-kuma
ExecStart=/usr/bin/npm start
Environment=UPTIME_KUMA_PORT=3001

[Install]
WantedBy=multi-user.target
UNIT

p7_info "Enabling service ..."
p7_ct_run "$CTID" <<'BASH'
systemctl daemon-reload
systemctl enable --now uptime-kuma
sleep 5
systemctl is-active uptime-kuma
BASH

CODE=$(p7_http_ok "http://${IP}:3001" 200 45 || true)
if [[ "$CODE" =~ ^(200|302|301)$ ]]; then
  p7_ok "Uptime Kuma HTTP ${CODE} at http://${IP}:3001 — create admin user on first visit."
else
  p7_error "Uptime Kuma did not come up (HTTP ${CODE}). pct exec ${CTID} -- journalctl -u uptime-kuma -n 50"
  exit 1
fi
