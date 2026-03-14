# 🏠 Homelab Media Stack
Self-hosted media and automation stack on Proxmox (`192.168.12.242`) with per-service LXCs, WireGuard/TinyProxy kill-switch routing, and dedicated HDD storage.

## 🏗️ Current Architecture
```
Tiamat (Proxmox) - 192.168.12.242
├── CT-100 wireguard    192.168.12.100  WireGuard server
├── CT-101 wg-proxy     192.168.12.101  WireGuard client + TinyProxy :8888
├── CT-102 flaresolverr 192.168.12.102  FlareSolverr :8191
├── CT-210 prowlarr     192.168.12.210
├── CT-212 qbittorrent  192.168.12.212
├── CT-214 sonarr       192.168.12.214
├── CT-215 radarr       192.168.12.215
├── CT-230 plex         192.168.12.230
├── CT-231 jellyfin     192.168.12.231
└── CT-900 ziggy        DHCP            Ollama runtime

Ziggy Pi - 192.168.12.20
├── AdGuard Home (primary DNS)
├── wg-easy
└── Vaultwarden + Caddy
```

## 🔐 Download VPN Path
`qBittorrent/Prowlarr -> CT-101 TinyProxy :8888 -> WG tunnel -> CT-100 -> internet`

CT-101 runs `wireguard-tools` + `tinyproxy` (container name may still mention gluetun, but software is WG+TinyProxy).

## 💾 Storage
- 2TB HDD mounted at `/mnt/hdd`
- Downloads: `/mnt/hdd/torrents/*`
- Libraries: `/mnt/hdd/media/*`
- Backups: `/mnt/hdd/backups`

### Ollama models
- Laptop exports models directory via NFS
- Proxmox mounts at `/mnt/laptop-models`
- CT-900 bind-mounts `/mnt/laptop-models`
- Ollama uses `OLLAMA_MODELS=/mnt/laptop-models`

## 📚 Docs
- `docs/PLAN.md`
- `docs/NETWORKING.md`
- `docs/PROXMOX-INSTALL.md`
- `docs/INDEXERS.md`
