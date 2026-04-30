# Jellyfin Autoscan
Three independent layers ensure Jellyfin always picks up new media — whether it
arrives via Sonarr/Radarr, the host's `rdt-client`, or a manual `cp`/`mv` into
`/mnt/media`. They overlap on purpose so a single failure never silently drops
a scan.
## Architecture
- Jellyfin runs natively in **CT-231** (`192.168.12.231:8096`).
- Sonarr (CT-214), Radarr (CT-225), and other *arr apps run on Tiamat.
- Media lives on the Proxmox host at `/mnt/media/{movies,tv,music}` and is
  bind-mounted into CT-231 read-only.
## The three layers
### Layer 1 — Real-time monitoring (inside Jellyfin)
Jellyfin uses inotify on `/data/movies`, `/data/tv`, `/data/music` and queues
a targeted folder rescan ~30–60s after a file lands. Configured per library
via `EnableRealtimeMonitor=true` in
`/var/lib/jellyfin/config/libraries/<lib>/options.xml`.
Enabled by `scripts/setup-jellyfin-autoscan.sh` for every library, then
Jellyfin is restarted to pick up the change.
### Layer 2 — Sonarr/Radarr → Jellyfin Connect notification
When the *arr apps import a release, they POST to Jellyfin's library API and
trigger an immediate rescan of just the affected path. This is the fastest
and most surgical option for *arr-driven imports.
Configured automatically by `scripts/media-pipeline-watchdog.py`
(`ensure_jellyfin_notification`). It runs every 5 minutes via
`media-pipeline-watchdog.timer` and re-creates the connection if it ever
disappears. Triggers wired: On Import, On Upgrade, On Rename, On Movie/Series
File Delete.
### Layer 3 — Host-side inotify watcher
For files that land in `/mnt/media` outside the *arr pipeline (manual drops,
rsync, `rdt-client` output you copy by hand), a systemd service on Tiamat
watches the same directories and POSTs `/Library/Refresh` with the Autoscan
API key. Independent of CT-231's own inotify, so it survives even if the LXC
loses inotify visibility for any reason.
Components:
- Watcher: `infrastructure/watchdogs/jellyfin-autoscan.sh`
- Unit:    `infrastructure/watchdogs/jellyfin-autoscan.service`
- Env:     `/etc/jellyfin-autoscan.env` (mode 0600, contains API key)
Default debounce window is 30s — rapid-fire copy events collapse into one
refresh.
### Layer 4 (safety net) — Scheduled "Scan Media Library"
The built-in Jellyfin task is set to an `IntervalTrigger` every 1 hour. If
Layers 1–3 all somehow fail, the scheduled scan still picks the file up.
## Deployment
Run on the Proxmox host (Tiamat) as root:
```bash
# 1. Configure Jellyfin (mint API key, enable real-time monitor, set scheduled scan)
bash /opt/homelab-media-stack/scripts/setup-jellyfin-autoscan.sh
# 2. Install the host-side inotify watcher
bash /opt/homelab-media-stack/scripts/install-host-autoscan.sh
# 3. Confirm the *arr → Jellyfin webhooks are in place
systemctl start media-pipeline-watchdog.service
journalctl -u media-pipeline-watchdog --since "5 min ago"
```
After step 1, `/etc/jellyfin-autoscan.env` contains:
```
JELLYFIN_URL=http://192.168.12.231:8096
JELLYFIN_API_KEY=<minted token>
```
Step 2 reads that file and adds `WATCH_DIRS` + `DEBOUNCE_SECONDS` if missing.
## Verification
```bash
# Jellyfin health + libraries
JELLYFIN_TOKEN=$(grep ^JELLYFIN_API_KEY /etc/jellyfin-autoscan.env | cut -d= -f2)
bash /opt/homelab-media-stack/scripts/validate-jellyfin.sh
# Real-time monitor flag in each library
pct exec 231 -- grep -l '<EnableRealtimeMonitor>true' /var/lib/jellyfin/config/libraries/*/options.xml
# Host watcher running
systemctl status jellyfin-autoscan
journalctl -u jellyfin-autoscan -n 20 --no-pager
# End-to-end: drop a test file, watch the journal
sudo touch /mnt/media/movies/.autoscan-test
journalctl -u jellyfin-autoscan -f
```
## Tuning
- **Debounce**: increase `DEBOUNCE_SECONDS` in `/etc/jellyfin-autoscan.env`
  if you do bulk imports (e.g. 120s) to avoid Jellyfin queueing many redundant
  scans. Reload with `systemctl restart jellyfin-autoscan`.
- **Scheduled scan period**: re-run setup with
  `SCAN_INTERVAL_HOURS=2 bash scripts/setup-jellyfin-autoscan.sh`.
- **inotify limits**: the installer sets
  `fs.inotify.max_user_watches=524288`. For libraries >250k files, raise to
  `1048576` via `INOTIFY_MAX_USER_WATCHES=1048576 bash scripts/install-host-autoscan.sh`.
## Atomic file drops
inotify only fires on completion when the file finishes via `close_write` or
`moved_to`. Always copy to a temp name on the same filesystem, then rename:
```bash
cp source.mkv /mnt/media/movies/.title.mkv.part
mv /mnt/media/movies/.title.mkv.part /mnt/media/movies/title.mkv
```
The watcher's `--exclude` already ignores `*.part`, `*.!qB`, `*.!ut`,
`/.tmp/`, and `*.swp` so partial files don't trigger refreshes.
## Troubleshooting
- *Layer 3 logs nothing on file drop*: confirm `WATCH_DIRS` are real
  directories on the host running the service (not inside CT-231). Check
  `systemctl cat jellyfin-autoscan` and `cat /etc/jellyfin-autoscan.env`.
- *Layer 1 misses files*: most often inotify watch limit was exhausted. Bump
  `fs.inotify.max_user_watches` and restart Jellyfin.
- *Layer 2 missing*: run `systemctl start media-pipeline-watchdog.service` and
  check the journal for `[FIXED] Sonarr: Jellyfin notification created`.
- *401 from `/Library/Refresh`*: rotate the Autoscan API key by deleting it in
  Jellyfin → Dashboard → API Keys, then re-run `setup-jellyfin-autoscan.sh`.
## Related
- `docs/MEDIA-PIPELINE-WATCHDOG.md` — full pipeline self-healing watchdog
- `scripts/validate-jellyfin.sh` — one-shot Jellyfin health check
- `scripts/verify-pipeline.sh` — end-to-end pipeline verification
