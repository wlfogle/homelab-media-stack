# Optimizations — Tiamat & Bahamut Media Stack

> Last updated: 2026-04-30

## Tiamat — Proxmox VE (192.168.12.242)

### Hardware
- **CPU**: AMD Ryzen 5 3600, 6c/12t
- **RAM**: 32GB DDR4-3200 (upgraded from 8GB)
- **Storage**: 240GB SSD (OS) + 2TB HDD (`/mnt/hdd` — media + downloads)
- **GPU**: RX 580 4GB (amdgpu — passed to CT-231 Jellyfin via /dev/dri for VAAPI; VFIO disabled)
- **Network**: Gigabit Ethernet

### Container RAM Allocation (applied 2026-04-10)

| Container | RAM | Swap | Notes |
|-----------|-----|------|-------|
| CT-100 wireguard | 768MB | 256MB | Bumped from 512MB (was at 90%+ usage) |
| CT-101 wg-proxy | 768MB | 256MB | Bumped from 512MB (was at 90%+ usage) |
| CT-103 traefik | 1024MB | 256MB | Bumped from 512MB (was at 90%+ usage) |
| CT-214 Sonarr | 2048MB | 512MB | Bumped from 1GB for larger libraries |
| CT-215 Radarr | 2048MB | 512MB | Bumped from 1GB for larger libraries |
| CT-230 Plex | 8GB | — | Transcoding benefits from RAM |
| CT-231 Jellyfin | 4GB | — | VAAPI hardware transcode via RX 580 (`/dev/dri` bind mount) |
| CT-212 qBittorrent | 2GB | — | Sufficient for heavy downloading |
| CT-210 Prowlarr | 1GB | — | Lightweight |
| CT-102 FlareSolverr | 1GB | — | Chrome headless needs RAM |

### VM-901 Windows Gaming
- **RAM**: 4GB, **CPU**: 4 cores, **cpulimit**: 2
- **KVM**: Enabled (`kvm: 1`) — was running with `kvm: 0` (TCG software emulation) causing load 28+
- **onboot**: Disabled — start manually when gaming, stop when done
- GPU passthrough: RX 580 via VFIO — **disabled** (amdgpu now default; re-add IDs to `/etc/modprobe.d/vfio.conf` if needed)

### Kernel Tuning (`/etc/sysctl.d/99-media-stack.conf`)
- `vm.swappiness = 10` — prefer RAM over swap
- `vm.dirty_ratio = 40` / `vm.dirty_background_ratio = 10` — batch HDD writes
- `vm.vfs_cache_pressure = 50` — keep filesystem caches longer
- `net.core.somaxconn = 4096` — handle many container connections
- `net.netfilter.nf_conntrack_max = 262144` — support 27+ containers
- `fs.inotify.max_user_watches = 524288` — *arr services watch many files
- TCP keepalive: 300s interval, 30s probe, 5 retries

### HDD I/O Tuning
- Readahead: 4096 sectors (2MB) for streaming workloads
- Persistent via `/etc/udev/rules.d/60-media-hdd.rules`
- BFQ I/O scheduler (default, good for mixed workloads)

### FileBrowser Quantum (v1.2.4-stable)
- Updated from v1.2.3-stable on 2026-04-10
- Config: `/usr/local/community-scripts/fq-config.yaml`
- `cacheDir: /tmp/filebrowser-cache` — fixes 51s slow startup on HDD
- Database: `/var/lib/filebrowser/database.db`
- Service hardened with `RestartSec=10`, `TimeoutStartSec=120`, `OOMScoreAdjust=-500`
- URL: `http://192.168.12.242:32743`

### Storage Layout
Hard-link friendly — downloads and media on same filesystem (`/mnt/hdd`):
```
/mnt/hdd/torrents/movies  →  /mnt/hdd/media/movies   (hard-link on import)
/mnt/hdd/torrents/tv      →  /mnt/hdd/media/tv       (hard-link on import)
/mnt/hdd/torrents/music   →  /mnt/hdd/media/music
/mnt/hdd/torrents/books   →  /mnt/hdd/media/books
```
All containers bind-mount `/mnt/hdd` → `/data` so paths are consistent.

### Transcoding
- **Jellyfin**: VAAPI hardware transcoding via RX 580 (`/dev/dri/renderD128` → CT-231).
  - amdgpu loaded on host; `blacklist amdgpu` removed from `/etc/modprobe.d/blacklist.conf`
  - vfio.conf GPU IDs removed so amdgpu claims GPU at boot
  - CT-231 LXC config: `lxc.cgroup2.devices.allow: c 226:0/128 rwm` + `/dev/dri` bind mount
  - Inside CT-231: `render` group GID set to 993, jellyfin user in `video` and `render` groups
  - Host udev rule `/etc/udev/rules.d/99-jellyfin-dri.rules`: `MODE="0666"` on renderD128 (unprivileged container needs world-readable device)
  - Note: `udevadm trigger` does not retroactively apply MODE to existing devices; `chmod 666 /dev/dri/renderD128` required after each boot until kernel fix
- **Plex**: CPU-only (CT-230 stopped, Jellyfin preferred)
- **Tdarr** (planned): Laptop RTX 4080 as NVENC transcoding worker.

### CT Startup Order Changes (2026-04-30)
- CT-231 Jellyfin: `order=3,up=30` (moved up to start early)
- CT-109 byparr: `order=2,up=15`
- CT-110/111 pulse: `order=2,up=15`
- CT-217 readarr, CT-218 lidarr, CT-221 mylar3, CT-232 audiobookshelf, CT-233 calibre-web: `onboot=0` (disabled)

### SQLite Database Maintenance (2026-04-30)
All *arr services + Jellyfin were experiencing `database is locked` errors causing failures and buffering.
Fix applied to: CT-231 Jellyfin, CT-210 Prowlarr, CT-214 Sonarr, CT-215 Radarr

```bash
# Run on Proxmox host to fix any arr service CT:
pct exec <CT> -- bash -c "systemctl stop <service>; \
  find /var/lib -name '*.db-wal' -o -name '*.db-shm' | xargs rm -fv; \
  find /var/lib -name '*.db' | while read db; do \
    sqlite3 \"\$db\" 'PRAGMA wal_checkpoint(TRUNCATE); VACUUM;'; done; \
  systemctl start <service>"
```

- Jellyfin: Slow plugins disabled — Spotify Import, IntroSkipper (moved to `/var/lib/jellyfin/plugins-disabled/`)
- TVHeadend plugin configured: admin@192.168.12.172:9981 (CT-231)

---

## Bahamut — Raspberry Pi 4B 2GB (192.168.12.244)

### Role
- AdGuard Home (network-wide DNS + ad-blocking)
- wg-easy (remote VPN access)
- Vaultwarden (password manager) + Caddy (TLS)
- Tailscale mesh VPN

### Memory Optimizations (applied 2026-04-10)
- **Swap**: Increased from 153MB to 1GB (`/var/swap`)
- **zram**: 512MB with lz4 compression at priority 100 (persistent via `zram-swap.service`)
- **GPU memory**: Reduced from 64MB to 16MB (headless, takes effect after reboot)
- **Docker memory limits**: Set in `/opt/docker-compose.yml` (requires cgroup memory, pending reboot)
  - AdGuard: 256MB, wg-easy: 128MB, Vaultwarden: 128MB, Caddy: 64MB

### Network Fix
- **Disabled wlan0**: Both eth0 (192.168.12.244) and wlan0 (192.168.12.245) were on the same subnet causing routing flaps. Wi-Fi disabled via `dtoverlay=disable-wifi` in boot config.

### Kernel Tuning (`/etc/sysctl.d/99-pi-optimize.conf`)
- `vm.swappiness = 60` — use swap more aggressively (only 2GB RAM)
- `vm.vfs_cache_pressure = 200` — reclaim caches quickly
- `vm.min_free_kbytes = 16384` — keep 16MB free to prevent OOM
- TCP keepalive: 300s interval, 30s probe, 5 retries

### Boot Config Changes (pending reboot)
- `cgroup_enable=memory cgroup_memory=1` in cmdline.txt (enables Docker memory limits)
- `gpu_mem=16` (frees ~48MB RAM)
- `dtoverlay=disable-wifi` (prevents dual-NIC routing issues)

---

## Network
- All CTs on bridged `vmbr0` → LAN `192.168.12.x`
- Static IPs for infrastructure (100-107) and download stack (210-224)
- DHCP for management CTs (240+) — routed via Traefik (`*.tiamat.local`)
- VPN kill-switch: qBit/Prowlarr → TinyProxy (CT-101:8888) → WG tunnel (CT-100)
