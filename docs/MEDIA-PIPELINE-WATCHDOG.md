# Media Pipeline Watchdog
Full-chain self-healing watchdog for the Seerr → Jellyfin pipeline. Runs every 5 minutes via systemd timer and auto-repairs problems at every link in the chain.

## What it does

### Phase 1 — Infrastructure health
- **VPN proxy**: verifies CT-101 TinyProxy is alive and exit IP is not your home IP
- **Jellyfin**: verifies `/health` returns Healthy
- **Prowlarr**: verifies applications are synced to Sonarr/Radarr and indexers exist
- **Jellyseerr**: verifies Sonarr and Radarr servers are configured

### Phase 2 — Per-app pipeline (Sonarr, Radarr, Readarr, Lidarr)
- Ensures qBittorrent download client exists (auto-creates if missing)
- Tests all enabled download clients for connectivity
- Ensures Jellyfin Connect notification exists (auto-creates if missing — triggers library scan on import)
- Removes poisoned releases (.exe, password-protected, etc.)
- Removes stale/failed queue items older than configured threshold
- App automatically re-searches for clean releases

### Phase 3 — Hooks
- Runs any configured webhook hooks (e.g. Discord notifications)

## Poisoned release patterns
- `.exe`
- `executable file`
- `password protected`
- `rar password`
- `contains executable`

## Files
- Script: `scripts/media-pipeline-watchdog.py`
- Sample config: `config/media-pipeline-watchdog.sample.json`
- systemd service: `infrastructure/watchdogs/media-pipeline-watchdog.service`
- systemd timer: `infrastructure/watchdogs/media-pipeline-watchdog.timer`
- One-shot diagnostic: `scripts/verify-pipeline.sh`

## Config sections

The JSON config has these top-level keys:

- `vpn_proxy` — VPN kill-switch proxy URL, test URL, optional home IP
- `jellyfin` — Jellyfin URL and API key (used for auto-creating Connect notifications)
- `prowlarr` — Prowlarr URL and API key
- `jellyseerr` — Jellyseerr URL and optional API key
- `qbittorrent` — qBit connection details and category mapping
- `apps` — array of arr apps (Sonarr, Radarr, Readarr, Lidarr, etc.)
- `hooks` — optional webhooks to fire after each run
- `stale_hours` — hours before a failed/warning queue item is auto-removed (default: 24)

See `config/media-pipeline-watchdog.sample.json` for a complete example.

## Deployment on Tiamat
Copy the script to `/usr/local/bin/media-pipeline-watchdog.py`, copy a real config to `/etc/media-pipeline-watchdog.json`, install the service/timer units, then run:

```bash
systemctl daemon-reload
systemctl enable --now media-pipeline-watchdog.timer
systemctl start media-pipeline-watchdog.service
```

## One-shot pipeline diagnostic
To verify every link without waiting for the timer:
```bash
bash scripts/verify-pipeline.sh
```
Reports pass/fail/warn for each of the 8 pipeline stages. Override endpoints and API keys via env vars.

## Adding future apps
Add another object to `apps` in the config with:
- `name`
- `url`
- `api_version`
- `api_key`
- `media_kind`

Supported `media_kind` values map to qBit categories:
- `tv`
- `movie`
- `book`
- `music`
- `adult`
