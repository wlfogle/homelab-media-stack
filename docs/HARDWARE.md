# Hardware Documentation

## Server — CyberPowerPC C Series ET8890-37125 (Tiamat @ 192.168.12.242)

> Specs confirmed via SSH + PowerShell query on 2026-03-13

| Component | Spec |
|-----------|------|
| **CPU** | AMD Ryzen 5 3600, 6-core / 12-thread, 3.6GHz base / 4.2GHz boost |
| **RAM** | 8GB DDR4 @ 3000MHz — single stick, **3 slots free** |
| **GPU** | XFX Radeon RX 580 Series, 4GB VRAM, Driver 31.0.21924.61 |
| **Motherboard** | Gigabyte B450M DS3H WIFI-CF (MicroATX, AM4 socket) |
| **Storage (OS)** | 240GB WD SSD |
| **Storage (Media)** | 2TB WD HDD |
| **Storage (External)** | 240GB Kingston SSD (USB) + 2GB USB flash drive |
| **PSU** | 450W |
| **Networking** | Gigabit Ethernet + 802.11AC Wi-Fi (onboard) |
| **OS** | Windows 10 Home 64-bit, Build 19045 |
| **Build date** | ~March 2020 |
| **Chassis** | Full tower, tempered glass side panel |
| **Service number** | 888-937-5582 |

## Recommended Upgrades

1. **RAM**: Add 1-3x 8GB or 16GB DDR4-3200 sticks (3 slots free, B450M DS3H supports up to 128GB across 4 slots)
   - 8GB limits concurrent LXC containers on Proxmox — 16-32GB total strongly recommended before deploying full stack
2. **OS**: Windows 10 Home reached end of life October 2025 — plan migration to Proxmox VE
3. **Storage**: Add a dedicated SSD for Proxmox root + container volumes, keep 2TB HDD for media
4. **Network**: Use wired Ethernet for the server (not Wi-Fi) for streaming stability

## Raspberry Pi 3B+

| Component | Spec |
|-----------|------|
| **CPU** | ARM Cortex-A53, 4-core 1.4GHz (64-bit capable, running 32-bit OS) |
| **RAM** | 1GB LPDDR2 |
| **Storage** | microSD (class 10 / A1 recommended, 16GB+) |
| **Networking** | 10/100 Ethernet + 802.11AC Wi-Fi (use wired) |
| **OS** | Raspberry Pi OS Lite (32-bit) |
| **Services** | Pi-hole (primary), WireGuard, Vaultwarden |

> Vaultwarden requires HTTPS. Use Caddy as a reverse proxy on the Pi for automatic TLS.

## Client Devices

| Device | Role |
|--------|------|
| Fire TV | Primary media playback + paid streaming apps |
| Tablet | Media requests (Overseerr), monitoring dashboards |
| Laptop | Proxmox admin, service management, browser dashboards |

## Network Requirements

- All devices on the same LAN for local streaming
- Server should have a static LAN IP (set via router DHCP reservation or Proxmox static config)
- Gigabit router/switch recommended for smooth 1080p/4K local streaming
