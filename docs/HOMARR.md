# Homarr Dashboard Setup

Homarr v1 (homarr-labs) runs on **CT-275** at `http://192.168.12.241:7575`.
Configuration is done through the web UI — there are no JSON config files in v1.

## First Login

1. Open `http://192.168.12.241:7575`
2. Create admin account (or use existing: `homarr` / `eVSdq6xAF5pJFr9!`)
3. Create a new board → name it **Tiamat**

## Board Layout — Apps to Add

Add each app via **Add tile → App**. Set the URL, icon (auto-detected from URL), and assign to the appropriate category section.

### Media Servers
| App | URL | Icon |
|-----|-----|------|
| Jellyfin | http://192.168.12.231:8096 | jellyfin |
| Plex | http://192.168.12.230:32400/web | plex |

### Media Acquisition (*arr Stack)
| App | URL | Icon |
|-----|-----|------|
| Sonarr | http://192.168.12.214:8989 | sonarr |
| Radarr | http://192.168.12.225:7878 | radarr |
| Readarr | http://192.168.12.217:8787 | readarr |
| Lidarr | http://192.168.12.218:8686 | lidarr |
| Mylar3 | http://192.168.12.221:8090 | mylar |
| Bazarr | http://192.168.12.188:6767 | bazarr |

### Indexers & Download Clients
| App | URL | Icon |
|-----|-----|------|
| Prowlarr | http://192.168.12.210:9696 | prowlarr |
| Jackett | http://192.168.12.211:9117 | jackett |
| qBittorrent | http://192.168.12.212:8080 | qbittorrent |
| RDT-Client | http://192.168.12.213:6500 | rdt-client |

### Request & Management
| App | URL | Icon |
|-----|-----|------|
| Jellyseerr | http://192.168.12.151:5055 | jellyseerr |
| Overseerr | http://192.168.12.224:5055 | overseerr |
| Tautulli | http://192.168.12.169:8181 | tautulli |

### Libraries
| App | URL | Icon |
|-----|-----|------|
| Audiobookshelf | http://192.168.12.232:13378 | audiobookshelf |
| Calibre-Web | http://192.168.12.233:8083 | calibre-web |

### Infrastructure
| App | URL | Icon |
|-----|-----|------|
| Proxmox | https://192.168.12.242:8006 | proxmox |
| Traefik | http://192.168.12.103:8080 | traefik |
| Vaultwarden | https://192.168.12.104 | vaultwarden |
| Authentik | http://192.168.12.107:9000 | authentik |
| FlareSolverr | http://192.168.12.102:8191 | flaresolverr |

### AI
| App | URL | Icon |
|-----|-----|------|
| Open WebUI (Ziggy) | http://192.168.12.250:3000 | open-webui |

### Bahamut (Pi)
| App | URL | Icon |
|-----|-----|------|
| AdGuard Home | http://192.168.12.244:3000 | adguard-home |
| DietPi Dashboard | http://192.168.12.244:5252 | dietpi |

## Widgets to Add

Homarr v1 supports several useful widgets via **Add tile → Widget**:

- **Clock** — top of board
- **Weather** — set your location
- **Docker containers** — shows running/stopped status (requires docker.sock mount)
- **Iframe** — embed Tautulli activity or Grafana panels
- **Ping** — add pings for critical services (Jellyfin, Prowlarr, qBittorrent)

## Integrations

Homarr v1 supports native integrations for *arr apps and media servers.
Go to **Settings → Integrations** and add:

| Integration | URL | API Key |
|-------------|-----|---------|
| Sonarr | http://192.168.12.214:8989 | 9e2127824e7446f6a2ddc5da67cfe693 |
| Radarr | http://192.168.12.225:7878 | cc7485c9f5a64f78bfd226ffe23e2991 |
| Readarr | http://192.168.12.217:8787 | 19566aa7fb90487ebd2c643ad8c6595d |
| Lidarr | http://192.168.12.218:8686 | 3ff130f5566448e4bc0ce42bdf24c24e |
| Prowlarr | http://192.168.12.210:9696 | 6719026a4a5042a99897597122fa4495 |
| Jellyfin | http://192.168.12.231:8096 | (generate in Jellyfin → Dashboard → API Keys) |

These integrations enable calendar widgets, download activity, and library stats on the board.

## Access From Clients

| Client | URL |
|--------|-----|
| Laptop browser | http://192.168.12.241:7575 |
| Android / Fire TV | http://homarr.tiamat.local (via Traefik) |
| Remote (Tailscale) | http://192.168.12.241:7575 (via Tailscale mesh) |
