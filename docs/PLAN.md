# Deployment Plan

## Architecture Summary

```
Router (192.168.12.1)
├── DNS 1: 192.168.12.102 (AdGuard Home — Proxmox LXC, primary)
├── DNS 2: 192.168.12.20  (AdGuard Home — Pi 3B+, replica)
└── DNS 3: 1.1.1.1        (Cloudflare fallback — network never dies)

Tiamat — Proxmox VE 9.x (192.168.12.10)
├── CT-100 (192.168.12.100) — WireGuard VPN Server (Alpine)
│   └── Self-hosted VPN — routes qBittorrent traffic
├── CT-101 (192.168.12.101) — Gluetun Proxy / TinyProxy (Alpine, privileged)
│   └── HTTP proxy on :8888 — qBittorrent/Prowlarr tunnel through here
├── CT-102 (192.168.12.102) — AdGuard Home primary (Debian)
│   └── Network-wide ad blocking + adguardhome-sync → Pi replica
└── CT-110 (192.168.12.110) — Media Stack (Debian, 4GB RAM, 4 cores)
    ├── Jellyfin     :8096
    ├── Sonarr       :8989
    ├── Radarr       :7878
    ├── Prowlarr     :9696
    ├── qBittorrent  :9090  ← routes through CT-101 proxy
    ├── Overseerr    :5055
    └── Bazarr       :6767

Raspberry Pi 3B+ (192.168.12.20)
├── AdGuard Home replica (synced from CT-102)
├── wg-easy :51821 — remote access VPN for clients
└── Vaultwarden + Caddy :443 — password manager

Storage (on Proxmox host)
├── /mnt/media/movies    → CT-110 bind mount
├── /mnt/media/tv        → CT-110 bind mount
├── /mnt/media/music     → CT-110 bind mount
├── /mnt/downloads       → CT-110 bind mount (qBit downloads here)
└── /mnt/media/backups   → daily vzdump snapshots

Client Devices
├── Fire TV  — Jellyfin app + native paid streaming (Netflix etc.)
├── Tablet   — Jellyfin + Overseerr + Bitwarden + WireGuard
└── Laptop   — Full admin via browser + SSH
```

## Deployment Order

### Phase 1 — Proxmox Host
1. Boot Tiamat from Ventoy USB → select Proxmox VE 9.0 ISO
2. Install: target 240GB SSD, hostname `tiamat`, IP `192.168.12.10`
3. SSH into Proxmox: `ssh root@192.168.12.10`
4. Clone repo: `git clone https://github.com/wlfogle/homelab-media-stack.git /opt/homelab-media-stack`
5. Run: `bash /opt/homelab-media-stack/scripts/setup-proxmox.sh`
6. Mount 2TB HDD (see proxmox/storage.conf)

### Phase 2 — Deploy Containers
7. Run: `bash /opt/homelab-media-stack/scripts/deploy-media-stack.sh`
8. Verify all 4 containers started: `pct list`

### Phase 3 — WireGuard VPN (for qBittorrent)
9. `pct exec 100 -- sh -c "cd /opt/homelab-media-stack/infrastructure/wireguard-server && sh setup-wg-server.sh"`
10. Copy client config from CT-100 to CT-101
11. `pct exec 101 -- sh -c "cd /opt/homelab-media-stack/infrastructure/wireguard-server && sh setup-gluetun-client.sh"`
12. Test: `pct exec 101 -- curl -x http://localhost:8888 ifconfig.me`

### Phase 4 — AdGuard Home
13. Browse to `http://192.168.12.102:3000` → complete setup wizard
14. Set admin password, configure upstream DNS (1.1.1.1, 8.8.8.8)
15. Add blocklists (see below)
16. Update router DNS: 1=192.168.12.102, 2=192.168.12.20, 3=1.1.1.1

### Phase 5 — Media Stack Config
17. Browse to each service and complete initial setup:
    - Jellyfin: add media libraries pointing to /data/movies, /data/tv, /data/music
    - Prowlarr: add indexers
    - Sonarr/Radarr: connect to Prowlarr + qBittorrent, set download paths
    - qBittorrent: Settings → Connection → Proxy → HTTP → 192.168.12.101:8888
    - Prowlarr: Settings → General → Proxy → HTTP → 192.168.12.101:8888
    - Overseerr: connect to Jellyfin + Sonarr + Radarr

### Phase 6 — Raspberry Pi
18. Image SD card with Raspberry Pi OS Lite 64-bit (Bookworm)
    - Enable SSH, set hostname `pi`, connect ethernet
19. SSH in: `ssh pi@192.168.12.20` (or find IP via router)
20. `sudo bash /path/to/setup-pi.sh` (or clone repo first)
21. Configure wg-easy: set `WG_HOST` to your public IP or DDNS
22. Forward port 51820/UDP on router to 192.168.12.20

### Phase 7 — Backup
23. Test backup: `bash /opt/homelab-media-stack/scripts/backup.sh`
24. Add cron: `0 3 * * * /opt/homelab-media-stack/scripts/backup.sh`

## Recommended AdGuard Home Blocklists
- AdGuard DNS filter: `https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt`
- EasyList: `https://easylist.to/easylist/easylist.txt`
- EasyPrivacy: `https://easylist.to/easylist/easyprivacy.txt`
- Steven Black Hosts: `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`

## VPN Kill Switch Verification
```bash
# Confirm qBittorrent traffic goes through VPN
pct exec 101 -- curl -x http://localhost:8888 ifconfig.me
# Output should NOT be your home IP

# Stop WireGuard — qBittorrent should lose internet access
pct exec 101 -- wg-quick down wg0
pct exec 101 -- curl -x http://localhost:8888 ifconfig.me --max-time 5
# Should timeout — kill switch working

# Restore VPN
pct exec 101 -- wg-quick up wg0
```
