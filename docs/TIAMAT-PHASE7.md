# Phase 7 — Extra Services Runbook
Adds six services to Tiamat that community-scripts.org publishes, all deployed natively (no Docker-in-LXC) and wired to the existing *arr / Jellyfin stack.
## CT / IP layout
| CTID | Hostname | IP | Port | Purpose |
|------|----------|-----|------|---------|
| 216 | decluttarr | 192.168.12.216 | — | *arr queue janitor (stalled/blocked removals) |
| 234 | threadfin | 192.168.12.234 | 34400 | M3U / XMLTV proxy for Jellyfin Live TV |
| 235 | dispatcharr | 192.168.12.235 | 9191 | IPTV stream + EPG manager |
| 245 | recyclarr | 192.168.12.245 | — | TRaSH-guide sync to Sonarr/Radarr (cron 03:45) |
| 247 | jellystat | 192.168.12.247 | 3000 | Jellyfin usage/playback stats |
| 248 | uptime-kuma | 192.168.12.248 | 3001 | Self-hosted uptime/health monitoring |
Replaces / retires: `CT-244 tautulli` (Plex-only), `CT-245 kometa` (Plex-centric), `CT-277 recyclarr` (empty shell).
## One-shot deploy
```bash
# On Tiamat (Proxmox host) as root
git -C /opt/homelab-media-stack pull
PHASE7_DESTROY_STALE=1 bash /opt/homelab-media-stack/scripts/deploy-phase7.sh
```
Flags:
- `PHASE7_DESTROY_STALE=1` — destroys stopped CT-244/245/277 before install (idempotent).
- `ONLY="recyclarr jellystat"` — run only the listed services.
- `SKIP="dispatcharr"` — skip services.
- `FORCE_RECREATE=1` — per-service flag to rebuild the CT from scratch.
## Single-service deploys
Each service has its own idempotent script:
```bash
bash /opt/homelab-media-stack/scripts/deploy-recyclarr.sh
bash /opt/homelab-media-stack/scripts/deploy-jellystat.sh
bash /opt/homelab-media-stack/scripts/deploy-decluttarr.sh
bash /opt/homelab-media-stack/scripts/deploy-uptimekuma.sh
bash /opt/homelab-media-stack/scripts/deploy-threadfin.sh
bash /opt/homelab-media-stack/scripts/deploy-dispatcharr.sh
```
All source `scripts/lib/phase7-common.sh` which provides CT lifecycle helpers, *arr API-key discovery, Jellyfin API-key minting, and HTTP health checks.
## Secrets handling
Nothing secret is stored in-repo. Deploy scripts **read at runtime**:
- Sonarr/Radarr/Readarr/Lidarr API keys from `/var/lib/*/config.xml` inside each CT
- Jellyfin API key from `/var/lib/jellyfin/data/jellyfin.db` on CT-231 (auto-mints a dedicated `Jellystat` key if one doesn't exist)
- Postgres passwords are generated via `openssl rand` at install time and written only to CT-internal `.env` files (`600 root:root`)
## Traefik routes
`infrastructure/traefik/dynamic/phase7.yml` is deployed to `/etc/traefik/dynamic/phase7.yml` on CT-103 and hot-loaded. Routers:
- `jellystat.tiamat.local` → 192.168.12.247:3000
- `uptime.tiamat.local` / `uptimekuma.tiamat.local` → 192.168.12.248:3001
- `threadfin.tiamat.local` → 192.168.12.234:34400
- `dispatcharr.tiamat.local` → 192.168.12.235:9191
Recyclarr and Decluttarr have no UI.
## Per-service first-time setup
### Recyclarr (CT-245)
- Pre-wired config at `/root/.config/recyclarr/recyclarr.yml` with Sonarr + Radarr API keys auto-discovered. Uses TRaSH templates: `sonarr-v4-quality-profile-web-1080p`, `radarr-quality-profile-hd-bluray-web`.
- First manual sync: `pct exec 245 -- recyclarr sync`
- Nightly cron: `/etc/cron.d/recyclarr` runs `recyclarr sync` at 03:45.
- Logs: `pct exec 245 -- tail -f /root/.config/recyclarr/sync.log`
### Jellystat (CT-247)
- Postgres 15 + Node 22 installed locally. DB `jellystat`, user `jellystat`, password in `/opt/jellystat/.env`.
- Deploy script auto-mints a dedicated `Jellystat` API key against CT-231 Jellyfin and pre-seeds `JELLYFIN_URL` + `JELLYFIN_TOKEN` in the `.env`.
- First visit `http://192.168.12.247:3000` → create Jellystat admin user → the Jellyfin URL/token should already be populated; click **Connect**.
- Logs: `pct exec 247 -- journalctl -u jellystat -f`
### Decluttarr (CT-216)
- Config at `/etc/default/decluttarr` pre-wired with Sonarr/Radarr (+ Readarr/Lidarr if their API keys were discovered) and qBittorrent creds.
- Default behavior: removes failed, stalled, orphan, unmonitored, and missing-file downloads after 3 attempts with a 10-minute cycle.
- Safety tag: add `Don't Kill` tag to any qBit torrent you want exempt from stall removal.
- Logs: `pct exec 216 -- journalctl -u decluttarr -f`
### Uptime Kuma (CT-248)
- First visit `http://192.168.12.248:3001` → create admin → import the recommended monitor set (see below).
- Recommended monitors (copy-paste into Uptime Kuma → "Add New Monitor", type: HTTP(s)):
  - Jellyfin — `http://192.168.12.231:8096/health`
  - Sonarr — `http://192.168.12.214:8989/ping`
  - Radarr — `http://192.168.12.225:7878/ping`
  - Prowlarr — `http://192.168.12.210:9696/ping`
  - qBittorrent — `http://192.168.12.212:8080`
  - Jellystat — `http://192.168.12.247:3000`
  - Threadfin — `http://192.168.12.234:34400/web`
  - Dispatcharr — `http://192.168.12.235:9191`
  - Traefik — `http://192.168.12.103:8080`
  - AdGuard (Bahamut) — `http://192.168.12.244:8081`
  - Vaultwarden — `http://192.168.12.104`
  - Authentik — `http://192.168.12.107:9000`
- Replaces `scripts/stack-watchdog.sh` (keep the script for CLI ad-hoc checks, but disable the systemd timer).
### Threadfin (CT-234)
- First visit `http://192.168.12.234:34400/web` → setup wizard → load your M3U (can point at the laptop NFS mount: `file:///mnt/laptop/iptv/lou.m3u` if bind-mounted, or upload via UI) and an XMLTV source.
- Configure Threadfin as a Jellyfin Live TV tuner: Jellyfin Dashboard → Live TV → Tuners → "M3U Tuner" → URL = `http://192.168.12.234:34400/m3u/threadfin.m3u`.
- Logs: `pct exec 234 -- journalctl -u threadfin -f`
### Dispatcharr (CT-235)
- First visit `http://192.168.12.235:9191` → create admin → import M3U + EPG.
- Four systemd units: `dispatcharr` (gunicorn :5656), `dispatcharr-daphne` (ws :8001), `dispatcharr-celery`, `dispatcharr-celerybeat`. Nginx on :9191 fronts them.
- Postgres DB `dispatcharr_db`, Redis on localhost:6379, credentials in `/opt/dispatcharr/.env` (600).
- Logs: `pct exec 235 -- journalctl -u dispatcharr -u dispatcharr-celery -u dispatcharr-daphne -f`
## Verification
```bash
# On Tiamat
for p in "216:decluttarr:journal" "245:recyclarr:cron" \
         "247:3000:jellystat" "248:3001:uptime-kuma" \
         "234:34400:threadfin" "235:9191:dispatcharr"; do
  IFS=: read -r ct port name <<<"$p"
  case "$port" in
    journal|cron)
      state=$(pct exec "$ct" -- systemctl is-active "$name" 2>/dev/null || echo n/a)
      echo "  CT-$ct $name = $state"
      ;;
    *)
      ip="192.168.12.$ct"
      code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 5 "http://$ip:$port" || echo 000)
      echo "  CT-$ct $name ($ip:$port) HTTP $code"
      ;;
  esac
done
```
## Troubleshooting
- **DNS fails inside a freshly-created CT** — the Proxmox network namespace can take 10–30 s to attach the veth to `vmbr0` on some kernels. `p7_ct_start_and_wait` retries for 30 s, then bails. If you hit the failure, wait a bit and re-run the same deploy script — they are all idempotent and skip the CT create step when the CT already exists.
- **Recyclarr "command not found"** — PATH inside `pct exec` is minimal; `scripts/lib/phase7-common.sh` now exports `/usr/local/bin` in `p7_ct_run`. If you bypass that wrapper, call `/usr/local/bin/recyclarr` by full path.
- **Jellyfin API key missing** — if `jellyfin.db` has no keys, log into Jellyfin → Dashboard → API Keys → create one, then `FORCE_RECREATE=1 bash scripts/deploy-jellystat.sh`.
- **Recyclarr/Decluttarr see wrong Radarr URL** — Radarr (CT-215) has static IP `192.168.12.225` (not `.215`) — baked into both scripts.
## Rollback
```bash
# On Tiamat
for ct in 216 234 235 245 247 248; do
  pct stop $ct 2>/dev/null
  pct destroy $ct --purge 1 2>/dev/null
done
rm -f /etc/traefik/dynamic/phase7.yml  # on CT-103
```
