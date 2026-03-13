# 🏠 Homelab Media Stack

A complete self-hosted media center and services platform built on **Proxmox VE**, designed for a desktop server with laptop, tablet, and Fire TV as client/control devices.

## 🏗️ Architecture

```
Desktop PC (Proxmox VE Host @ 192.168.12.10)
├── LXC: Media Stack (Jellyfin, Sonarr, Radarr, qBittorrent, Overseerr)
├── LXC: Infrastructure (Traefik, Pi-hole secondary)
├── LXC: Monitoring (Grafana, Prometheus, Uptime Kuma)
└── Storage: /mnt/media (movies, shows, music)

Raspberry Pi 3B+ (@ 192.168.12.20)
├── Pi-hole (primary DNS + ad-block)
├── WireGuard (VPN server)
└── Vaultwarden (password manager)

Client Devices
├── Fire TV       → Jellyfin app + native paid streaming apps
├── Tablet        → Media requests (Overseerr) + admin dashboards
└── Laptop        → Proxmox web UI + full admin access
```

## 📁 Repository Structure

```
homelab-media-stack/
├── proxmox/              # Proxmox host configuration
│   ├── network.conf      # Static IP and bridge config
│   └── storage.conf      # Storage pool definitions
├── media-stack/          # Media service docker-compose files
│   ├── jellyfin/
│   ├── sonarr/
│   ├── radarr/
│   ├── qbittorrent/
│   └── overseerr/
├── infrastructure/       # Core infra services
│   ├── traefik/
│   └── pihole/           # Secondary Pi-hole (Proxmox LXC)
├── pi/                   # Raspberry Pi 3B+ configuration
│   ├── pihole/           # Primary Pi-hole
│   ├── wireguard/
│   └── vaultwarden/
├── scripts/              # Setup and maintenance scripts
│   ├── setup-proxmox.sh
│   ├── deploy-media-stack.sh
│   └── backup.sh
├── clients/              # Client device setup guides
│   ├── firetv.md
│   ├── tablet.md
│   └── laptop.md
└── docs/                 # Documentation
    ├── PLAN.md
    ├── HARDWARE.md
    └── NETWORKING.md
```

## 🚀 Deployment Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Proxmox install + networking + storage | 🔲 |
| 2 | Core infrastructure (Traefik, Pi-hole) | 🔲 |
| 3 | Media stack (Jellyfin, Sonarr, Radarr, qBittorrent) | 🔲 |
| 4 | Client integration (Fire TV, Tablet, Laptop) | 🔲 |
| 5 | Pi 3B+ setup (Pi-hole primary, WireGuard, Vaultwarden) | 🔲 |
| 5a | Security hardening | 🔲 |
| 6 | Monitoring (Grafana, Prometheus) | 🔲 |

## 🖥️ Hardware

See [docs/HARDWARE.md](docs/HARDWARE.md) for full specs.

**Server:** CyberPowerPC C Series ET8890-37125
- AMD Ryzen 5 3600 (6-core 3.6GHz)
- 8GB DDR4 RAM *(upgrade to 16-32GB recommended)*
- XFX AMD Radeon GPU
- 240GB SSD + 2TB HDD
- 450W PSU
- 802.11AC Wi-Fi + Gigabit Ethernet

## 📋 Requirements

- Proxmox VE 9.x
- Docker + Docker Compose (inside LXC containers)
- Static LAN IP on the server
- All client devices on the same LAN (or WireGuard for remote)

## 📚 Related

- [awesome-stack](https://github.com/wlfogle/awesome-stack) — Full self-hosting infrastructure this builds toward
