#!/usr/bin/env bash
# ============================================================
# Deploy TVHeadend — CT-236 (192.168.12.236)
#
# Fully automated: creates LXC, installs TVHeadend, builds
# hdhomerun_config from source, configures HDHomeRun IPTV
# network via API, maps all OTA channels.
#
# Access after deploy:
#   Web UI:  http://192.168.12.236:9981
#   HTSP:    192.168.12.236:9982  (Jellyfin / TVHPlayer)
#   M3U:     http://192.168.12.236:9981/playlist/channels.m3u
#   XMLTV:   http://192.168.12.236:9981/xmltv/channels
#
# Run from Proxmox host (192.168.12.242):
#   bash scripts/deploy-tvheadend.sh
#
# Env:
#   FORCE_RECREATE=1   destroy CT-236 and rebuild
# ============================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/phase7-common.sh"

CT_ID=236
CT_IP="192.168.12.236"
CT_HOSTNAME="tvheadend"

# HDHomeRun tuner on LAN
HDHOMERUN_IP="192.168.12.215"
HDHOMERUN_M3U="http://${HDHOMERUN_IP}:5004/lineup.m3u"

p7_step "TVHeadend → CT-${CT_ID} @ ${CT_IP}:9981"
p7_require_pve
[ "${FORCE_RECREATE:-0}" = "1" ] && p7_ct_destroy_if_exists "$CT_ID"

# ── Create CT ──────────────────────────────────────────────────
p7_ct_create "$CT_ID" "$CT_HOSTNAME" "$CT_IP" 2 1024 8 \
  --unprivileged 0 --startup order=4,up=30
# Allow multicast (HDHomeRun discovery)
grep -q 'lxc.cap.drop' /etc/pve/lxc/${CT_ID}.conf 2>/dev/null || \
  echo "lxc.cap.drop =" >> /etc/pve/lxc/${CT_ID}.conf
p7_ct_start_and_wait "$CT_ID"

# ── Install build tools + hdhomerun_config from source ───────
p7_info "Installing build tools and dependencies..."
p7_ct_run "$CT_ID" <<'BASH'
apt-get install -y --no-install-recommends \
  build-essential git curl wget ca-certificates \
  gnupg apt-transport-https python3 libssl-dev
BASH

p7_info "Building hdhomerun_config from SiliconDust source..."
pct exec $CT_ID -- bash -c "
  cd /tmp
  rm -rf libhdhomerun*
  VER=\$(curl -sf 'https://api.github.com/repos/Silicondust/libhdhomerun/releases/latest' \
    | grep -oP '"tag_name": *"\K[^"]+' 2>/dev/null || echo 'v20250303')
  URL=\"https://github.com/Silicondust/libhdhomerun/archive/refs/tags/\${VER}.tar.gz\"
  echo \"Downloading libhdhomerun \$VER...\"
  wget -qO hdhomerun.tar.gz \"\$URL\" || \
    wget -qO hdhomerun.tar.gz https://github.com/Silicondust/libhdhomerun/archive/refs/heads/master.tar.gz
  tar xzf hdhomerun.tar.gz
  cd libhdhomerun-*
  make -j\$(nproc) 2>&1 | tail -3
  cp hdhomerun_config /usr/local/bin/
  chmod +x /usr/local/bin/hdhomerun_config
  echo 'Built: ' \$(hdhomerun_config --version 2>&1 || hdhomerun_config 2>&1 | head -1)
"

# ── Install TVHeadend ─────────────────────────────────────────
p7_info "Installing TVHeadend..."
pct exec $CT_ID -- bash -c "
  export DEBIAN_FRONTEND=noninteractive

  # Try Cloudsmith repo (most reliable for TVH stable)
  curl -fsSL 'https://dl.cloudsmith.io/public/tvheadend/tvheadend/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/tvheadend.gpg 2>/dev/null

  if [ -f /usr/share/keyrings/tvheadend.gpg ]; then
    echo 'deb [signed-by=/usr/share/keyrings/tvheadend.gpg] https://dl.cloudsmith.io/public/tvheadend/tvheadend/deb/debian bookworm main' \
      > /etc/apt/sources.list.d/tvheadend.list
    apt-get update -qq
    apt-get install -y tvheadend && echo 'TVH installed from Cloudsmith repo' && exit 0
  fi

  # Fallback: apt.tvheadend.org
  curl -fsSL 'https://apt.tvheadend.org/stable/tvheadend.gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/tvheadend-apt.gpg 2>/dev/null || true
  echo 'deb [signed-by=/usr/share/keyrings/tvheadend-apt.gpg] https://apt.tvheadend.org/stable/ bookworm main' \
    > /etc/apt/sources.list.d/tvheadend-apt.list
  apt-get update -qq && apt-get install -y tvheadend && echo 'TVH installed from apt.tvheadend.org' && exit 0

  echo 'ERROR: Could not install TVHeadend from any source'; exit 1
"

# ── Configure TVHeadend service ───────────────────────────────
p7_info "Configuring TVHeadend service..."
pct exec $CT_ID -- bash -c "
  cat > /etc/default/tvheadend <<'SVCEOF'
TVH_ARGS="-C -u hts -g video --http_port 9981 --htsp_port 9982 --nosatip"
SVCEOF

  systemctl enable tvheadend
  systemctl restart tvheadend

  echo 'Waiting for TVHeadend HTTP API (up to 60s)...'
  for i in \$(seq 1 20); do
    curl -sf http://localhost:9981/api/serverinfo &>/dev/null && echo 'API ready' && break
    sleep 3
  done
"

# ── Set open LAN access (no login required on local network) ──
p7_info "Configuring open LAN access control..."
pct exec $CT_ID -- bash -c "
  TVH_CFG=/home/hts/.hts/tvheadend
  for i in \$(seq 1 10); do [ -d \"\$TVH_CFG\" ] && break; sleep 2; done
  mkdir -p \"\$TVH_CFG/accesscontrol\"
  cat > \"\$TVH_CFG/accesscontrol/default\" <<'ACLEOF'
{
  \"index\": 1,
  \"enabled\": true,
  \"username\": \"*\",
  \"prefix\": \"0.0.0.0/0,::/0\",
  \"uilevel\": -1,
  \"uilevel_nochange\": -1,
  \"streaming\": [\"basic\",\"advanced\",\"htsp\"],
  \"dvr\": [\"basic\",\"htsp\",\"all\",\"all_rw\",\"failed\"],
  \"webui\": true,
  \"admin\": true,
  \"conn_limit_type\": 0,
  \"comment\": \"Default LAN access\"
}
ACLEOF
  chown -R hts:hts \"\$TVH_CFG\"
  systemctl restart tvheadend
  sleep 5
"

# ── Configure HDHomeRun IPTV network via TVH API ──────────────
p7_info "Creating HDHomeRun IPTV auto-network via API..."
pct exec $CT_ID -- bash -c "
  TVH='http://localhost:9981'
  for i in \$(seq 1 15); do
    curl -sf \"\$TVH/api/serverinfo\" &>/dev/null && break
    sleep 3
  done

  RESULT=\$(curl -sf -X POST \"\$TVH/api/mpegts/network/create\" \
    -d 'class=iptv_auto_network' \
    -d 'conf={\"networkname\":\"HDHomeRun CONNECT\",\"url\":\"${HDHOMERUN_M3U}\",\"max_streams\":1,\"scan_create\":true,\"service_sid\":1,\"skipinitscan\":false}' 2>&1)
  echo \"Network create: \$RESULT\"

  NET_UUID=\$(echo \"\$RESULT\" | python3 -c 'import sys,json; print(json.load(sys.stdin).get(\"uuid\",\"\"))' 2>/dev/null || echo '')
  if [ -n \"\$NET_UUID\" ]; then
    echo \"Network UUID: \$NET_UUID\"
    curl -sf -X POST \"\$TVH/api/mpegts/network/scan\" -d \"uuid=\$NET_UUID\" && echo 'Scan triggered'
  else
    echo 'WARNING: Could not create network — configure manually at http://${CT_IP}:9981'
  fi
"

# ── Wait for scan, then map services → channels ───────────────
p7_info "Waiting 90s for channel scan to complete..."
pct exec $CT_ID -- bash -c "
  TVH='http://localhost:9981'
  sleep 90

  SVC_UUIDS=\$(curl -sf \"\$TVH/api/service/list?enum=1\" \
    | python3 -c 'import sys,json; print(\",\".join(e[\"key\"] for e in json.load(sys.stdin)[\"entries\"]))' 2>/dev/null || echo '')
  COUNT=\$(echo \"\$SVC_UUIDS\" | tr ',' '\n' | grep -c . 2>/dev/null || echo 0)
  echo \"Services discovered: \$COUNT\"

  if [ \"\$COUNT\" -gt 0 ]; then
    UUID_JSON=\$(echo \"\$SVC_UUIDS\" | python3 -c \"
import sys
uuids = sys.stdin.read().strip().split(',')
print('[' + ','.join('\\\"'+u+'\\\"' for u in uuids if u) + ']')
\" 2>/dev/null || echo '[]')
    curl -sf -X POST \"\$TVH/api/service/mapper/save\" \
      -d \"node={\\\"services\\\":\${UUID_JSON},\\\"check_availability\\\":false,\\\"encrypted\\\":true,\\\"merge_same_name\\\":true}\" \
      && echo 'Services mapped to channels'
  else
    echo 'No services found yet — scan may still be running.'
    echo 'Check http://${CT_IP}:9981 → Configuration → DVB Inputs → Services'
  fi

  # Summary
  NET_INFO=\$(curl -sf \"\$TVH/api/mpegts/network/grid\" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); n=d[\"entries\"][0] if d[\"entries\"] else {}; print(f\"mux:{n.get(\\\"num_mux\\\",0)} svc:{n.get(\\\"num_svc\\\",0)} chn:{n.get(\\\"num_chn\\\",0)}\")' 2>/dev/null || echo \"?\")
  echo \"Final network state: \$NET_INFO\"
"

CODE=$(p7_http_ok "http://${CT_IP}:9981" 200 20 || true)
if [[ "$CODE" =~ ^(200|302|301|401)$ ]]; then
  p7_ok "TVHeadend HTTP ${CODE} at http://${CT_IP}:9981"
else
  p7_error "TVHeadend did not respond. pct exec ${CT_ID} -- journalctl -u tvheadend -n 50"
fi

p7_ok "
CT-$CT_ID TVHeadend deployed and configured.

  Web UI:    http://$CT_IP:9981   (no login required on LAN)
  HTSP:      $CT_IP:9982          (Jellyfin / TVHPlayer / Kodi)
  M3U:       http://$CT_IP:9981/playlist/channels.m3u
  XMLTV:     http://$CT_IP:9981/xmltv/channels
  HDHomeRun: $HDHOMERUN_IP

Jellyfin Live TV (CT-231 / http://192.168.12.231:8096):
  Dashboard → Live TV → Tuner Hosts → Add → HD HomeRun
    URL: http://$CT_IP
  Listing Providers → Add → XMLTV
    Path: http://$CT_IP:9981/xmltv/channels

TVHPlayer:
  Server URL: http://$CT_IP:9981  (no login)

Laptop TVHeadend (backup):
  Web UI:  http://192.168.12.172:9981
  HTSP:    192.168.12.172:9982

See docs/TVHEADEND.md for the full guide.
============================================================
"
