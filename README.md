# 🏠 Homelab Media Stack

A complete self-hosted media center and services platform built on **Proxmox VE**, designed for a desktop server with laptop, tablet, and Fire TV as client/control devices.

## 🏗️ Architecture

```
Tiamat — Proxmox VE 9.x (192.168.12.10)
├── CT-100 (192.168.12.100) — WireGuard VPN server (qBittorrent kill-switch)
├── CT-101 (192.168.12.101) — Gluetun + TinyProxy (HTTP proxy :8888)
├── CT-102 (192.168.12.102) — AdGuard Home primary (DNS ad-blocking)
└── CT-110 (192.168.12.110) — Media Stack
    ├── Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent
    ├── Overseerr, Bazarr, Traefik
    ├── Homarr (unified dashboard :7575)
    └── MediaStack Control (container manager :9900)

Raspberry Pi 3B+ (192.168.12.20)
├── AdGuard Home replica (synced from CT-102 every 5 min)
├── wg-easy (remote access VPN :51820)
└── Vaultwarden + Caddy (password manager :443)

Client Devices
├── Fire TV  → Jellyfin + Silk Browser (Overseerr/Homarr) + sideloaded nzb360
├── Android  → Jellyfin + nzb360 (arr control) + Overseerr + Homarr
└── Laptop   → Full admin (Proxmox, Homarr, MediaStack Control, SSH)
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
│   ├── adguardhome/      # AdGuard Home (Proxmox CT-102)
│   └── wireguard-server/ # WireGuard VPN server (CT-100) + Gluetun proxy (CT-101)
├── pi/                   # Raspberry Pi 3B+ configuration
│   ├── adguardhome/      # AdGuard Home replica
│   ├── wireguard/        # wg-easy remote access VPN
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
| 2 | Core infrastructure (Traefik, AdGuard Home, WireGuard VPN) | 🔲 |
| 3 | Media stack (Jellyfin, Sonarr, Radarr, qBittorrent, Homarr) | 🔲 |
| 4 | Client setup (Fire TV, Android, Laptop — nzb360, Overseerr) | 🔲 |
| 5 | Pi 3B+ setup (AdGuard replica, wg-easy, Vaultwarden) | 🔲 |
| 5a | Security hardening | 🔲 |
| 6 | Monitoring (MediaStack Control, Uptime Kuma) | 🔲 |

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
