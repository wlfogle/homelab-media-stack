#!/usr/bin/env bash
# ============================================================
# Phase 7 — Dispatcharr (CT-235 @ 192.168.12.235:9191)
#
# Full IPTV stream / EPG manager (Django + Celery + Daphne +
# Redis + nginx + PostgreSQL). Mirrors community-scripts'
# install/dispatcharr-install.sh without the interactive wrapper.
#
# Run on Proxmox host (Tiamat):
#   bash /opt/homelab-media-stack/scripts/deploy-dispatcharr.sh
#
# Env:
#   FORCE_RECREATE=1   destroy CT-235 and rebuild
# ============================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/phase7-common.sh"

CTID=235
HOSTNAME=dispatcharr
IP=192.168.12.235

p7_step "Dispatcharr → CT-${CTID} @ ${IP}:9191"
p7_require_pve
[ "${FORCE_RECREATE:-0}" = "1" ] && p7_ct_destroy_if_exists "$CTID"

# 2CPU / 2 GB / 8 GB per upstream defaults
p7_ct_create "$CTID" "$HOSTNAME" "$IP" 2 2048 8
p7_ct_start_and_wait "$CTID"

p7_info "Installing system deps (postgres, redis, nginx, ffmpeg, vlc, streamlink, python3-dev) ..."
p7_ct_run "$CTID" <<'BASH'
apt-get update -qq
apt-get install -y --no-install-recommends -qq \
  curl ca-certificates gnupg git build-essential \
  python3 python3-dev python3-venv python3-pip \
  libpq-dev nginx redis-server ffmpeg procps \
  vlc-bin vlc-plugin-base streamlink \
  postgresql postgresql-contrib openssl tzdata
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo America/New_York > /etc/timezone

# Node 24 for frontend
if ! command -v node >/dev/null 2>&1 || ! node --version | grep -q '^v24'; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y --no-install-recommends -qq nodejs
fi
# uv package manager (python)
if ! command -v uv >/dev/null 2>&1; then
  curl -fsSL https://astral.sh/uv/install.sh | sh
  ln -sf /root/.local/bin/uv /usr/local/bin/uv
fi
node --version; uv --version
BASH

p7_info "Creating PostgreSQL DB + user ..."
DB_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c24)
DJANGO_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c50)
export DB_PASS DJANGO_SECRET

p7_ct_run "$CTID" <<BASH
systemctl enable --now postgresql redis-server >/dev/null
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='dispatcharr_usr'" | grep -q 1 \
  && sudo -u postgres psql -c "ALTER USER dispatcharr_usr WITH PASSWORD '${DB_PASS}';" >/dev/null \
  || sudo -u postgres psql -c "CREATE USER dispatcharr_usr WITH PASSWORD '${DB_PASS}';" >/dev/null
sudo -u postgres psql -lqt | cut -d'|' -f1 | grep -qw dispatcharr_db \
  || sudo -u postgres psql -c "CREATE DATABASE dispatcharr_db WITH OWNER dispatcharr_usr ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' TEMPLATE template0;" >/dev/null
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE dispatcharr_db TO dispatcharr_usr;" >/dev/null
sudo -u postgres psql -d dispatcharr_db -c "GRANT ALL ON SCHEMA public TO dispatcharr_usr;" >/dev/null
BASH

p7_info "Cloning Dispatcharr latest ..."
p7_ct_run "$CTID" <<'BASH'
set -Eeuo pipefail
rm -rf /opt/dispatcharr
mkdir -p /opt/dispatcharr /data/{logos,recordings,plugins,db} /data/uploads/{m3us,epgs} /data/{m3us,epgs}
TARBALL=$(curl -fsSL https://api.github.com/repos/Dispatcharr/Dispatcharr/releases/latest \
  | grep -oE '"tarball_url":\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
[ -n "$TARBALL" ] || { echo "Cannot find Dispatcharr tarball"; exit 1; }
curl -fsSL "$TARBALL" -o /tmp/dispatcharr.tar.gz
tar -xzf /tmp/dispatcharr.tar.gz -C /opt/dispatcharr --strip-components=1
rm -f /tmp/dispatcharr.tar.gz
chown -R root:root /data /opt/dispatcharr
BASH

p7_info "Setting up Python venv + deps (uv) ..."
p7_ct_run "$CTID" <<'BASH'
set -Eeuo pipefail
cd /opt/dispatcharr
uv venv --clear >/dev/null
uv sync 2>&1 | tail -n 10
uv pip install gunicorn gevent celery redis daphne 2>&1 | tail -n 5
BASH

p7_info "Writing /opt/dispatcharr/.env ..."
p7_ct_write "$CTID" /opt/dispatcharr/.env 0600 root:root <<ENV
DATABASE_URL=postgresql://dispatcharr_usr:${DB_PASS}@localhost:5432/dispatcharr_db
POSTGRES_DB=dispatcharr_db
POSTGRES_USER=dispatcharr_usr
POSTGRES_PASSWORD=${DB_PASS}
POSTGRES_HOST=localhost
CELERY_BROKER_URL=redis://localhost:6379/0
DJANGO_SECRET_KEY=${DJANGO_SECRET}
ENV

p7_info "Running Django migrate + collectstatic + building frontend ..."
p7_ct_run "$CTID" <<'BASH'
set -Eeuo pipefail
cd /opt/dispatcharr
set -a; source .env; set +a
uv run python manage.py migrate --noinput 2>&1 | tail -n 10
uv run python manage.py collectstatic --noinput 2>&1 | tail -n 5
cd /opt/dispatcharr/frontend
npm install --legacy-peer-deps --no-audit --no-fund 2>&1 | tail -n 10
npm run build 2>&1 | tail -n 10
BASH

p7_info "Configuring nginx on :9191 ..."
p7_ct_write "$CTID" /etc/nginx/sites-available/dispatcharr.conf 0644 root:root <<'NGINX'
server {
  listen 9191;
  server_name _;
  client_max_body_size 100M;

  location /assets/ {
    alias /opt/dispatcharr/frontend/dist/assets/;
    expires 30d;
    add_header Cache-Control "public, immutable";
    types {
      text/javascript js;
      text/css css;
      image/png png;
      image/svg+xml svg svgz;
      font/woff2 woff2;
      font/woff  woff;
      font/ttf   ttf;
    }
  }
  location /static/ { alias /opt/dispatcharr/static/; expires 30d; add_header Cache-Control "public, immutable"; }
  location /media/  { alias /opt/dispatcharr/media/; }
  location /ws/ {
    proxy_pass http://127.0.0.1:8001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
  location / {
    include proxy_params;
    proxy_pass http://127.0.0.1:5656;
  }
}
NGINX
p7_ct_run "$CTID" <<'BASH'
ln -sf /etc/nginx/sites-available/dispatcharr.conf /etc/nginx/sites-enabled/dispatcharr.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx
BASH

p7_info "Writing start scripts + four systemd units ..."
for name in gunicorn celery celerybeat daphne; do
  case $name in
    gunicorn)   cmd='uv run gunicorn --workers=4 --worker-class=gevent --timeout=300 --bind 0.0.0.0:5656 dispatcharr.wsgi:application' ;;
    celery)     cmd='uv run celery -A dispatcharr worker -l info -c 4' ;;
    celerybeat) cmd='uv run celery -A dispatcharr beat -l info' ;;
    daphne)     cmd='uv run daphne -b 0.0.0.0 -p 8001 dispatcharr.asgi:application' ;;
  esac
  p7_ct_write "$CTID" "/opt/dispatcharr/start-${name}.sh" 0755 root:root <<SH
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/dispatcharr
set -a; source .env; set +a
exec ${cmd}
SH
done

p7_ct_write "$CTID" /etc/systemd/system/dispatcharr.service 0644 root:root <<'UNIT'
[Unit]
Description=Dispatcharr Web Server (gunicorn)
After=network.target postgresql.service redis-server.service
[Service]
Type=simple
WorkingDirectory=/opt/dispatcharr
ExecStart=/opt/dispatcharr/start-gunicorn.sh
Restart=on-failure
RestartSec=10
User=root
[Install]
WantedBy=multi-user.target
UNIT
p7_ct_write "$CTID" /etc/systemd/system/dispatcharr-celery.service 0644 root:root <<'UNIT'
[Unit]
Description=Dispatcharr Celery Worker
After=network.target redis-server.service
Requires=dispatcharr.service
[Service]
Type=simple
WorkingDirectory=/opt/dispatcharr
ExecStart=/opt/dispatcharr/start-celery.sh
Restart=on-failure
RestartSec=10
User=root
[Install]
WantedBy=multi-user.target
UNIT
p7_ct_write "$CTID" /etc/systemd/system/dispatcharr-celerybeat.service 0644 root:root <<'UNIT'
[Unit]
Description=Dispatcharr Celery Beat Scheduler
After=network.target redis-server.service
Requires=dispatcharr.service
[Service]
Type=simple
WorkingDirectory=/opt/dispatcharr
ExecStart=/opt/dispatcharr/start-celerybeat.sh
Restart=on-failure
RestartSec=10
User=root
[Install]
WantedBy=multi-user.target
UNIT
p7_ct_write "$CTID" /etc/systemd/system/dispatcharr-daphne.service 0644 root:root <<'UNIT'
[Unit]
Description=Dispatcharr WebSocket Server (daphne)
After=network.target
Requires=dispatcharr.service
[Service]
Type=simple
WorkingDirectory=/opt/dispatcharr
ExecStart=/opt/dispatcharr/start-daphne.sh
Restart=on-failure
RestartSec=10
User=root
[Install]
WantedBy=multi-user.target
UNIT

p7_ct_run "$CTID" <<'BASH'
systemctl daemon-reload
systemctl enable --now dispatcharr dispatcharr-celery dispatcharr-celerybeat dispatcharr-daphne
sleep 6
systemctl is-active dispatcharr dispatcharr-celery dispatcharr-celerybeat dispatcharr-daphne | tr '\n' ' '
echo
BASH

CODE=$(p7_http_ok "http://${IP}:9191" 200 60 || true)
if [[ "$CODE" =~ ^(200|302|301)$ ]]; then
  p7_ok "Dispatcharr HTTP ${CODE} at http://${IP}:9191 — finish setup in UI + load M3U/EPG."
else
  p7_error "Dispatcharr did not come up. pct exec ${CTID} -- journalctl -u dispatcharr -n 60"
  exit 1
fi
