# Android (Tablet / Phone) Setup Guide

## Apps to Install

| App | Purpose | Source |
|-----|---------|--------|
| Jellyfin | Media playback | Play Store |
| nzb360 | Unified arr control (Sonarr, Radarr, qBit) | Play Store ($5) |
| Bitwarden | Password manager (Vaultwarden) | Play Store |
| WireGuard | Remote VPN access | Play Store |

## Media Playback
1. Install **Jellyfin** from Play Store
2. Add server: `http://192.168.12.110:8096`
3. Sign in and enjoy your media library

## Requesting & Managing Content

### nzb360 — Best option (native app, full control)
nzb360 is a unified controller for the entire arr stack — add shows, movies, manage downloads, search indexers, all from one native Android app.

1. Install **nzb360** from Play Store (~$5 one-time)
2. Open → tap the menu → add each service:
   - **Sonarr**: `http://192.168.12.110:8989` + API key
   - **Radarr**: `http://192.168.12.110:7878` + API key
   - **qBittorrent**: `http://192.168.12.110:9090`
   - **Prowlarr**: `http://192.168.12.110:9696` + API key

> Get API keys from each service: Settings → General → Security → API Key

### Overseerr — Simpler request-only option (free, browser)
1. Open Chrome → `http://192.168.12.110:5055`
2. Sign in with Jellyfin account
3. Search → click **Request** — Sonarr/Radarr handles the rest

### Homarr — Unified dashboard (browser)
1. Open Chrome → `http://192.168.12.110:7575`
2. See active downloads, queues, library stats, all services in one view
3. Add to home screen for app-like access

## Admin Dashboards (browser bookmarks)
| Service | URL |
|---------|-----|
| Homarr (unified) | http://192.168.12.110:7575 |
| Overseerr | http://192.168.12.110:5055 |
| Jellyfin | http://192.168.12.110:8096 |
| Sonarr | http://192.168.12.110:8989 |
| Radarr | http://192.168.12.110:7878 |
| Prowlarr | http://192.168.12.110:9696 |
| qBittorrent | http://192.168.12.110:9090 |
| AdGuard Home | http://192.168.12.102 |
| wg-easy | http://192.168.12.20:51821 |
| Vaultwarden | https://192.168.12.20 |

## Bitwarden / Vaultwarden
1. Install **Bitwarden** from Play Store
2. Settings → Self-hosted → Server URL: `https://192.168.12.20`
3. Create account and start saving passwords

## Remote Access (WireGuard)
1. Install **WireGuard** from Play Store
2. Open wg-easy: `http://192.168.12.20:51821` → create client → scan QR code
3. Toggle VPN on when away from home — all services accessible as if on LAN
