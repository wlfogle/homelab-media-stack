# Laptop Setup Guide

**Machine**: Intel Core i9-13900HX, 62.5 GB RAM, RTX 4080, Pop!_OS 22.04
The laptop is the **primary admin device** for the full stack.

## Admin Access

| Service | URL | Notes |
|---------|-----|-------|
| **Homarr** (unified dashboard) | http://192.168.12.110:7575 | Start here — links to everything |
| **MediaStack Control** | http://192.168.12.110:9900 | Container mgmt, logs, system stats |
| Proxmox Web UI | https://192.168.12.50:8006 | Accept self-signed cert warning |
| Jellyfin | http://192.168.12.110:8096 | |
| Overseerr | http://192.168.12.110:5055 | Request movies/TV |
| Sonarr | http://192.168.12.110:8989 | |
| Radarr | http://192.168.12.110:7878 | |
| Prowlarr | http://192.168.12.110:9696 | |
| qBittorrent | http://192.168.12.110:9090 | |
| Bazarr | http://192.168.12.110:6767 | |
| AdGuard Home | http://192.168.12.102 | |
| wg-easy | http://192.168.12.20:51821 | |
| Vaultwarden | https://192.168.12.20 | |

## SSH Access

```bash
# Proxmox host
ssh root@192.168.12.50

# Enter LXC containers
ssh root@192.168.12.50 "pct exec 110 -- bash"  # Media stack
ssh root@192.168.12.50 "pct exec 102 -- bash"  # AdGuard Home
ssh root@192.168.12.50 "pct exec 100 -- sh"    # WireGuard server
ssh root@192.168.12.50 "pct exec 101 -- sh"    # Gluetun proxy
ssh root@192.168.12.50 "pct exec 150 -- bash"  # Fire TV controller

# Raspberry Pi
ssh pi@192.168.12.20
```

## Passwordless SSH Setup
```bash
ssh-copy-id root@192.168.12.50
ssh-copy-id pi@192.168.12.20
```

## Useful Commands

```bash
# Check all container status on Proxmox
ssh root@192.168.12.50 "pct list"

# Check media stack Docker containers
ssh root@192.168.12.50 "pct exec 110 -- docker ps"

# Restart media stack
ssh root@192.168.12.50 "pct exec 110 -- bash -c 'cd /opt/homelab-media-stack/media-stack && docker compose restart'"

# Update all Docker images
ssh root@192.168.12.50 "pct exec 110 -- bash -c 'cd /opt/homelab-media-stack/media-stack && docker compose pull && docker compose up -d'"

# Check AdGuard Home logs
ssh root@192.168.12.50 "pct exec 102 -- docker logs adguardhome --tail 50"

# Check WireGuard tunnel status
ssh root@192.168.12.50 "pct exec 100 -- wg show"

# Check Fire TV controller
ssh root@192.168.12.50 "pct exec 150 -- systemctl status firetv-controller"

# Build + sideload TiamatsStack APK to all Fire TVs
cd /opt/homelab-media-stack/android-app && ./build-app.sh install-firetv
```

## Bitwarden (Vaultwarden)
1. Install **Bitwarden** browser extension
2. Settings → Self-hosted → Server URL: `https://192.168.12.20`
3. Create your account

## Remote Access (WireGuard)
1. Install WireGuard: `sudo nala install wireguard`
2. Open wg-easy at `http://192.168.12.20:51821`
3. Create client → download config
4. `sudo wg-quick up /path/to/config.conf`
