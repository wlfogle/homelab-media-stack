# Media Stack Credentials & Access URLs

> IPs verified against live Proxmox on 2026-04-24

## Media Servers
| CT | Service | URL | User | Pass | Status |
|---|---|---|---|---|---|
| CT-231 | Jellyfin | http://192.168.12.231:8096 | jellyfin | jellyfin | ✅ running (4 cores, 8GB RAM) |
| CT-230 | Plex | http://192.168.12.230:32400/web | loufogle (Plex account) | — | ⏹ stopped |

## Live TV / OTA
| CT | Service | URL | Notes | Status |
|---|---|---|---|---|
| — | HDHomeRun CONNECT | http://192.168.12.215 | Device ID: 1048EEE4, 2 tuners, 46 OTA channels | ✅ active |
| — | HDHomeRun M3U | http://192.168.12.215:5004/lineup.m3u | Direct from device | ✅ active |
| Laptop | TVHeadend (snap) | http://192.168.12.172:9981 | Web UI — no login on LAN, 46 channels mapped | ✅ running |
| Laptop | TVHeadend HTSP | 192.168.12.172:9982 | For Jellyfin/TVHPlayer | ✅ running |
| Laptop | TVH M3U (served) | http://192.168.12.172:8765/hdhomerun.m3u | systemd HTTP server | ✅ running |
| Laptop | EPG XMLTV | http://192.168.12.172:8766/epg.xml | zap2xml (75ch, 16K programmes, daily 3:30AM) | ✅ running |
| CT-231 | Jellyfin Live TV | http://192.168.12.231:8096 | HDHomeRun tuner + XMLTV EPG, DVR → /data/media/recordings | ✅ configured |
| Laptop | TVH DVR | /mnt/tiamat-recordings | NFS mount → Tiamat /mnt/hdd/media/recordings | ✅ mounted |

## Alexa Bridge
| CT | Service | URL | Notes | Status |
|---|---|---|---|---|
| CT-200 | Caddy HTTPS proxy | https://ha.lou-fogle-media-stack.duckdns.org | Let's Encrypt cert, reverse proxy → HA 192.168.12.123:8123 | ✅ running |
| VM-990 | Home Assistant | http://192.168.12.123:8123 | HAOS, user: loufogle/homeassist | ✅ running |

## Download Stack
| CT | Service | URL | User/API Key | Status |
|---|---|---|---|---|
| CT-212 | qBittorrent | http://192.168.12.212:8080 | admin / adminadmin | ✅ running |
| CT-210 | Prowlarr | http://192.168.12.210:9696 | API: 6719026a4a5042a99897597122fa4495 | ✅ running |
| CT-211 | Jackett | http://192.168.12.211:9117 | — | ✅ running |
| CT-214 | Sonarr | http://192.168.12.214:8989 | API: 9e2127824e7446f6a2ddc5da67cfe693 | ✅ running |
| CT-215 | Radarr | http://192.168.12.225:7878 | API: cc7485c9f5a64f78bfd226ffe23e2991 | ✅ running |
| CT-217 | Readarr | http://192.168.12.217:8787 | API: 19566aa7fb90487ebd2c643ad8c6595d | ✅ running |
| CT-218 | Lidarr | http://192.168.12.218:8686 | API: 3ff130f5566448e4bc0ce42bdf24c24e | ✅ running |
| CT-221 | Mylar3 | http://192.168.12.221:8090 | — | ✅ running |
| CT-213 | RDT-Client | http://192.168.12.213:6500 | admin / Rdtclient2026! | ✅ running |

## Media Management
| CT | Service | URL | User | Pass | Status |
|---|---|---|---|---|---|
| CT-242 | Jellyseerr | http://192.168.12.151:5055 | seerr@local | seerr | ✅ running |
| CT-241 | Overseerr | http://192.168.12.224:5055 | — | — | ✅ running |
| CT-244 | Tautulli | http://192.168.12.169:8181 | tautulli | tautulli | ✅ running |
| CT-240 | Bazarr | http://192.168.12.188:6767 | none | — | ⏹ stopped |
| CT-277 | Recyclarr | http://192.168.12.141 | — | — | ✅ running |
| CT-245 | Kometa | — | — | — | ⏹ stopped |

## Libraries
| CT | Service | URL | User | Pass | Status |
|---|---|---|---|---|---|
| CT-232 | Audiobookshelf | http://192.168.12.232:13378 | (set on first login) | — | ✅ running |
| CT-233 | Calibre-Web | http://192.168.12.233:8083 | calibre | calibre | ✅ running |

## Dashboards & Tools
| CT | Service | URL | Status |
|---|---|---|---|
| CT-275 | Homarr | http://192.168.12.241:7575 | ✅ running | homarr / eVSdq6xAF5pJFr9! |
| CT-950 | Pulse | http://192.168.12.251:7655 | ✅ running | (set on first login) |
| CT-276 | Homepage | — | ⏹ stopped |
| CT-103 | Traefik | http://192.168.12.103:8080 | ✅ running |
| CT-900 | Open WebUI (Ziggy) | http://192.168.12.250:3000 | ⏹ stopped (onboot: 0) |
| CT-109 | Byparr | http://192.168.12.109:8191 | ✅ running (replaced FlareSolverr) |
| CT-102 | FlareSolverr | http://192.168.12.102:8191 | ⏹ deprecated → use CT-109 Byparr |
| CT-280 | RetroArch Web | — | ⏹ stopped |
| — | Quantum (File Browser) | http://192.168.12.242:32743 | quantum / quantum |

## Infrastructure
| CT | Service | URL | User | Pass | Status |
|---|---|---|---|---|---|
| CT-100 | WireGuard | 192.168.12.100:51820/udp | — | — | ✅ running |
| CT-101 | WG-Proxy (TinyProxy) | http://192.168.12.101:8888 | — | — | ✅ running |
| CT-104 | Vaultwarden | https://192.168.12.104 | (create account) | — | ✅ running |
| CT-105 | Valkey (Redis) | 192.168.12.105:6379 | — | — | ✅ running |
| CT-106 | PostgreSQL | 192.168.12.106:5432 | — | — | ✅ running |
| CT-107 | Authentik | http://192.168.12.107:9000 | — | — | ✅ running |
| CT-279 | Tailscale | 192.168.12.220 | — | — | ✅ running |
| CT-278 | CrowdSec | — | — | — | ⏹ stopped |
| — | Proxmox | https://192.168.12.242:8006 | root | (your root pw) | ✅ host |

## Bahamut (Raspberry Pi 4B — 192.168.12.244)
| Service | URL | User | Pass |
|---|---|---|---|
| AdGuard Home | http://192.168.12.244:3000 | adguard | (your pw) |
| wg-easy | http://192.168.12.244:51821 | — | (hashed pw) |
| Vaultwarden | https://192.168.12.244 (via Caddy) | (create account) | — |
| DietPi Dashboard | http://192.168.12.244:5252 | (DietPi login) | — |

## Remote Access
| Service | URL | Notes |
|---|---|---|
| Jellyfin (Tailscale Funnel) | https://tiamat-tailscale.tail9d8b73.ts.net/ | Public internet, no VPN needed |
| Jellyfin (LAN) | http://192.168.12.231:8096 | Local network only |

## VNC
| System | Address | Display | Notes |
|---|---|---|---|
| Tiamat | 192.168.12.242:5900 | :0 (x11vnc) | GPU-rendered (RX 580), use this one |
| Bahamut | 192.168.12.244:5901 | :1 (Xtigervnc + Warp) | |

Laptop launcher: "Tiamat (VNC)" in app menu → `xtigervncviewer 192.168.12.242:5900`

## NFS Mounts (Laptop)
| Mount Point | Source | Mode |
|---|---|---|
| /mnt/tiamat-media | 192.168.12.242:/mnt/hdd/media | read-only (full library) |
| /mnt/tiamat-recordings | 192.168.12.242:/mnt/hdd/media/recordings | read-write (DVR) |

## API Keys Reference
| Service | Key |
|---|---|
| Prowlarr | 6719026a4a5042a99897597122fa4495 |
| Sonarr | 9e2127824e7446f6a2ddc5da67cfe693 |
| Radarr | cc7485c9f5a64f78bfd226ffe23e2991 |
| Readarr | 19566aa7fb90487ebd2c643ad8c6595d |
| Lidarr | 3ff130f5566448e4bc0ce42bdf24c24e |
| Plex Token | mixMERF9aEJxg9HrDzZW |
| TMDb | 47ef060c8451984321a70c2a07c63bce |
| Real Debrid | S637QWEA454DIRAVGD5MKVAU7CH62FMASOSSXQNY5ERTJCFKINKQ |
| Jellyfin (Oz-Agent) | 849ce95e446c4fbaa6b948c4d548b0eb |
