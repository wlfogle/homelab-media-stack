#!/usr/bin/env bash
# ============================================================
# Phase 7 — Jellystat (CT-247 @ 192.168.12.247:3000)
#
# Jellyfin playback/usage statistics. Native install using the
# same step sequence as community-scripts/ProxmoxVED addon, but
# headless and idempotent.
#
# Auto-mints a dedicated "Jellystat" API key against CT-231
# Jellyfin using an existing Jellyseerr admin key.
#
# Run on Proxmox host (Tiamat):
#   bash /opt/homelab-media-stack/scripts/deploy-jellystat.sh
#
# Env:
#   FORCE_RECREATE=1   destroy CT-247 and rebuild
# ============================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/phase7-common.sh"

CTID=247
HOSTNAME=jellystat
IP=192.168.12.247
JELLYFIN_CTID=231
JELLYFIN_URL="http://192.168.12.231:8096"

p7_step "Jellystat → CT-${CTID} @ ${IP}:3000"
p7_require_pve
[ "${FORCE_RECREATE:-0}" = "1" ] && p7_ct_destroy_if_exists "$CTID"

p7_ct_create "$CTID" "$HOSTNAME" "$IP" 2 2048 8
p7_ct_start_and_wait "$CTID"

p7_info "Minting Jellyfin API key for Jellystat ..."
JELLYFIN_TOKEN=$(p7_jellyfin_key_get_or_create "$JELLYFIN_CTID" || true)
if [ -z "$JELLYFIN_TOKEN" ]; then
  p7_warn "Could not auto-mint Jellyfin API key — Jellystat will work but UI setup will require you to paste a key manually."
  JELLYFIN_TOKEN=""
fi

p7_info "Installing Node 22 + PostgreSQL + build deps in CT-${CTID} ..."
p7_ct_run "$CTID" <<'BASH'
apt-get update -qq
apt-get install -y --no-install-recommends -qq \
  curl ca-certificates gnupg git build-essential \
  postgresql postgresql-contrib \
  python3 openssl tzdata
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo America/New_York > /etc/timezone

# Node 22 via Nodesource
if ! command -v node >/dev/null 2>&1 || ! node --version | grep -q '^v22'; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y --no-install-recommends -qq nodejs
fi
node --version
BASH

p7_info "Creating PostgreSQL database + user ..."
DB_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c24)
JWT_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c32)
export DB_PASS JWT_SECRET

p7_ct_run "$CTID" <<BASH
systemctl enable --now postgresql >/dev/null
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='jellystat'" | grep -q 1 \
  && sudo -u postgres psql -c "ALTER USER jellystat WITH PASSWORD '${DB_PASS}';" >/dev/null \
  || sudo -u postgres psql -c "CREATE USER jellystat WITH PASSWORD '${DB_PASS}';" >/dev/null
sudo -u postgres psql -lqt | cut -d'|' -f1 | grep -qw jellystat \
  || sudo -u postgres psql -c "CREATE DATABASE jellystat WITH OWNER jellystat ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' TEMPLATE template0;" >/dev/null
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE jellystat TO jellystat;" >/dev/null
sudo -u postgres psql -d jellystat -c "GRANT ALL ON SCHEMA public TO jellystat;" >/dev/null

# Ensure password auth on localhost
PG_HBA=\$(sudo -u postgres psql -tAc "SHOW hba_file;" | tr -d ' ')
if ! grep -qE "^host\\s+jellystat\\s+jellystat\\s+127.0.0.1" "\$PG_HBA"; then
  sed -i "/^# IPv4 local connections:/a host    jellystat    jellystat    127.0.0.1/32    scram-sha-256" "\$PG_HBA"
  sed -i "/^# IPv4 local connections:/a host    jellystat    jellystat    ::1/128         scram-sha-256" "\$PG_HBA"
  systemctl reload postgresql
fi
BASH

p7_info "Cloning + building Jellystat latest release ..."
p7_ct_run "$CTID" <<'BASH'
set -Eeuo pipefail
rm -rf /opt/jellystat
mkdir -p /opt/jellystat
TARBALL=$(curl -fsSL https://api.github.com/repos/CyferShepard/Jellystat/releases/latest \
  | grep -oE '"tarball_url":\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
[ -n "$TARBALL" ] || { echo "Could not find Jellystat tarball"; exit 1; }
curl -fsSL "$TARBALL" -o /tmp/jellystat.tar.gz
tar -xzf /tmp/jellystat.tar.gz -C /opt/jellystat --strip-components=1
rm -f /tmp/jellystat.tar.gz

cd /opt/jellystat
npm install --omit=optional --no-audit --no-fund 2>&1 | tail -n 20
npm run build 2>&1 | tail -n 20
BASH

p7_info "Writing /opt/jellystat/.env ..."
p7_ct_write "$CTID" /opt/jellystat/.env 0600 root:root <<ENV
# Managed by scripts/deploy-jellystat.sh
# Database
POSTGRES_USER=jellystat
POSTGRES_PASSWORD=${DB_PASS}
POSTGRES_IP=localhost
POSTGRES_PORT=5432
POSTGRES_DB=jellystat

# Security
JWT_SECRET=${JWT_SECRET}

# Server
JS_LISTEN_IP=0.0.0.0
JS_BASE_URL=/
TZ=America/New_York

# Jellyfin bootstrap (pastes into UI on first load)
JELLYFIN_URL=${JELLYFIN_URL}
JELLYFIN_TOKEN=${JELLYFIN_TOKEN}

REJECT_SELF_SIGNED_CERTIFICATES=true
ENV

p7_info "Writing systemd unit ..."
p7_ct_write "$CTID" /etc/systemd/system/jellystat.service 0644 root:root <<'UNIT'
[Unit]
Description=Jellystat - Statistics for Jellyfin
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/jellystat/backend
EnvironmentFile=/opt/jellystat/.env
ExecStart=/usr/bin/node /opt/jellystat/backend/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

p7_info "Starting jellystat.service ..."
p7_ct_run "$CTID" <<'BASH'
systemctl daemon-reload
systemctl enable --now jellystat
sleep 3
systemctl is-active jellystat
BASH

CODE=$(p7_http_ok "http://${IP}:3000" 200 30 || true)
if [[ "$CODE" =~ ^(200|302|301)$ ]]; then
  p7_ok "Jellystat HTTP ${CODE} at http://${IP}:3000"
  if [ -n "$JELLYFIN_TOKEN" ]; then
    p7_ok "Jellyfin URL + dedicated API key pre-seeded in /opt/jellystat/.env."
    p7_info "First-time setup: visit http://${IP}:3000, create admin account; Jellyfin connection block uses env defaults."
  else
    p7_warn "Jellyfin token not pre-seeded — paste one in the Jellystat setup wizard."
  fi
else
  p7_error "Jellystat did not come up (HTTP ${CODE}). Logs: pct exec ${CTID} -- journalctl -u jellystat -n 50"
  exit 1
fi
