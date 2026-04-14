# 🏠 Homelab Media Stack

Self-hosted media and automation stack on Proxmox (`192.168.12.242`) with per-service LXCs, WireGuard/TinyProxy kill-switch routing, Real-Debrid via RDT-Client, and dedicated HDD storage.

## 🏗️ Current Architecture

```
Tiamat (Proxmox) - 192.168.12.242
├── Infrastructure
│   ├── CT-100 wireguard      192.168.12.100  WireGuard server
│   ├── CT-101 wg-proxy       192.168.12.101  WireGuard client + TinyProxy :8888
│   ├── CT-102 flaresolverr   192.168.12.102  FlareSolverr :8191 (nodriver fork)
│   ├── CT-103 traefik        192.168.12.103  Traefik reverse proxy
│   ├── CT-104 vaultwarden    192.168.12.104  Vaultwarden :80
│   ├── CT-105 valkey         192.168.12.105  Valkey (Redis) :6379
│   ├── CT-106 postgresql     192.168.12.106  PostgreSQL :5432
│   └── CT-107 authentik      192.168.12.107  Authentik SSO :9000
├── Indexers & Download Clients
│   ├── CT-210 prowlarr       192.168.12.210  :9696  (primary indexer manager)
│   ├── CT-211 jackett        192.168.12.211  :9117  (backup/failsafe indexers)
│   ├── CT-212 qbittorrent    192.168.12.212  :8080  (VPN proxied, backup dl client)
│   └── CT-213 rdtclient      192.168.12.213  :6500  (Real-Debrid, primary dl client)
├── Media Acquisition (*arr stack)
│   ├── CT-214 sonarr         192.168.12.214  :8989  (TV → RDT-Client)
│   ├── CT-215 radarr         192.168.12.225  :7878  (Movies → RDT-Client)
│   ├── CT-217 readarr        192.168.12.217  :8787  (Books → qBittorrent)
│   ├── CT-218 lidarr         192.168.12.218  :8686  (Music → qBittorrent)
│   └── CT-221 mylar3         192.168.12.221  :8090  (Comics → qBittorrent)
├── Media Servers
│   ├── CT-230 plex           192.168.12.230  :32400
│   └── CT-231 jellyfin       192.168.12.231  :8096  (primary)
├── Media Hosting
│   ├── CT-232 audiobookshelf 192.168.12.232  :13378 (audiobooks)
│   └── CT-233 calibre-web    192.168.12.233  :8083  (ebooks)
├── Request & Management
│   ├── CT-240 bazarr         DHCP            :6767  (subtitles)
│   └── CT-242 seerr          DHCP            :5055  (TV/movie requests)
├── Monitoring (stopped)
│   ├── CT-277 recyclarr      —               not installed, CT shell only
│   └── CT-278 crowdsec       —               stopped, deferred
├── Networking
│   └── CT-279 tailscale      192.168.12.220  Tailscale mesh VPN
└── AI
    └── CT-900 ziggy          DHCP            Open WebUI :3000 + SearXNG :8081

Bahamut (DietPi) - 192.168.12.244
├── AdGuard Home       :53, :8081  (DNS filtering, Docker)
├── Caddy + DuckDNS    :80, :443   (reverse proxy + SSL, Docker)
├── WG-Easy            :51820/udp  (WireGuard VPN mgmt, Docker)
├── Vaultwarden        :8080       (password manager, Docker)
├── DietPi Dashboard   :5252       (system monitoring)
├── TigerVNC           :5901       (remote desktop)
└── Tailscale                      (mesh VPN)

Laptop - 192.168.12.172
├── Ollama :11434 (RTX 4080 GPU, 41 models)
└── NFS shares → Tiamat
```

## 🔀 Download Split

TV and movies use Real-Debrid via RDT-Client (CT-213, Bezzad local downloader — no symlinks, no rclone). Books, music, and comics use qBittorrent (CT-212) over WireGuard VPN.

| App             | Download Client   | Path                                            |
| --------------- | ----------------- | ----------------------------------------------- |
| Sonarr (TV)     | RDT-Client :6500  | Real-Debrid → /data/downloads/rdtclient/sonarr/ |
| Radarr (Movies) | RDT-Client :6500  | Real-Debrid → /data/downloads/rdtclient/radarr/ |
| Readarr (Books) | qBittorrent :8080 | VPN                                             |
| Lidarr (Music)  | qBittorrent :8080 | VPN                                             |
| Mylar3 (Comics) | qBittorrent :8080 | VPN                                             |

## 🔍 Indexer Failsafe

Prowlarr (CT-210) is the primary indexer manager syncing to all *arr apps. Jackett (CT-211) is wired as backup Torznab indexers directly in Sonarr and Radarr at priority 50 (lower priority than Prowlarr at 25). If Prowlarr indexers get rate-limited or go down, Jackett indexers take over automatically.

## 📺 Jellyfin Notifications

All *arr apps with Jellyfin support have MediaBrowser notifications configured to trigger library refresh on import:

- Sonarr ✓, Radarr ✓, Lidarr ✓
- Readarr — not supported (no MediaBrowser notification type)

## 🌐 Traefik Routes (CT-103)

All services reachable via `*.tiamat.local` — see `docs/NETWORKING.md` for full table.
Traefik dashboard: `http://traefik.tiamat.local` (or `http://192.168.12.103:8080`)

## 🔐 Download VPN Path

`qBittorrent/Prowlarr -> CT-101 TinyProxy :8888 -> WG tunnel -> CT-100 -> internet`

CT-101 runs `wireguard-tools` + `tinyproxy`.

## 💾 Storage

- 2TB HDD mounted at `/mnt/hdd`
- Downloads: `/mnt/hdd/torrents/*`
- Libraries: `/mnt/hdd/media/*` (tv, movies, music, books, audiobooks, comics)
- Backups: `/mnt/hdd/backups`

### File Browser (Proxmox host :32654)

File Browser runs on the Proxmox host as a systemd service (`/etc/systemd/system/filebrowser.service`) with root dir `/`. It creates files with restrictive permissions (640/750) that unprivileged LXCs like Jellyfin (CT-231) cannot read. An `after_upload` command hook is configured to fix this automatically:

```
chmod 644 "$FILE" && chmod 755 "$(dirname "$FILE")"
```

This setting is stored in File Browser's BoltDB database at `/usr/local/community-scripts/filebrowser.db` and can be managed via the API (`PUT /api/settings`).

### Ollama (Laptop → CT-900)

- Laptop runs Ollama on RTX 4080 (12GB VRAM), bound to `0.0.0.0:11434`
- CT-900 runs Open WebUI (:3000) + SearXNG (:8081)
- Models stored on external drive, 41 models available

## 📱 Client Apps

- `android-app/` — TiamatsStack WebView app (mobile + Fire TV flavors)
- `clients/firetv.md` — Fire TV setup guide
- `clients/tablet.md` — Android phone/tablet setup guide
- `clients/laptop.md` — Laptop admin setup guide
- `clients/mediastack-control-popos/` — Native Tkinter desktop app for Pop!_OS
- `clients/desktop-launchers/` — `.desktop` launchers (MediaStack Control, Tiamat VNC)

## ⚠️ Known Issues

- Seerr 3.1.0 Jellyfin sync returns 400 ("Guid can't be empty" on /Items/Latest) — cosmetic, does not block requests. Fix expected in Seerr v3.2.0.
- CT-277 Recyclarr is an empty CT shell — not installed.
- CT-278 CrowdSec stopped and deferred.

## 📚 Docs

- `docs/PLAN.md` — Full deployment plan & container reference
- `docs/NETWORKING.md` — LAN layout, VPN architecture, service URLs
- `docs/AI.md` — Ollama + Open WebUI setup
- `docs/NFS.md` — Laptop NFS shares
- `docs/HARDWARE.md` — Server, Pi, laptop specs
- `docs/PROXMOX-INSTALL.md`
- `docs/PROXMOX-WIFI.md` — Connecting Proxmox to Wi-Fi
- `docs/HOMARR.md` — Homarr v1 dashboard board setup & integrations
- `docs/INDEXERS.md`
- `docs/BACKUPS.md`
- `docs/REAL-DEBRID.md`
- `docs/TIAMAT-AGENT-FIXES.md` — Fix runbooks for Readarr, Lidarr, Audiobookshelf, Calibre-Web, FlareSolverr
