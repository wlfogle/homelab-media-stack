# Networking

## LAN Layout

```
Router (192.168.12.1)
├── Desktop Server (Proxmox)  → 192.168.12.10  (static)
├── Tiamat (current Windows)  → 192.168.12.242 (pre-Proxmox)
├── Raspberry Pi 3B+          → 192.168.12.20  (static)
├── Fire TV                   → DHCP
├── Tablet                    → DHCP
└── Laptop                    → DHCP
```

## Proxmox Network Bridge

Proxmox uses a Linux bridge (`vmbr0`) to give LXC containers network access.

`/etc/network/interfaces` on Proxmox host:
```
auto lo
iface lo inet loopback

auto enp3s0
iface enp3s0 inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.12.10/24
    gateway 192.168.12.1
    bridge-ports enp3s0
    bridge-stp off
    bridge-fd 0

dns-nameservers 192.168.12.1
```

> Adjust `enp3s0` to match your actual NIC name (check with `ip link`).

## Service Port Map

### Proxmox Host (192.168.12.10)

| Service | Port | URL |
|---------|------|-----|
| Proxmox Web UI | 8006 | https://192.168.12.10:8006 |

### CT-102 — AdGuard Home (192.168.12.102)

| Service | Port | URL |
|---------|------|-----|
| AdGuard Home Web UI | 80 | http://192.168.12.102 |
| DNS | 53 | Set as DNS 1 on router |

### CT-110 — Media Stack (192.168.12.110)

| Service | Port | URL |
|---------|------|-----|
| **Homarr** (unified dashboard) | 7575 | http://192.168.12.110:7575 |
| **MediaStack Control** | 9900 | http://192.168.12.110:9900 |
| Jellyfin | 8096 | http://192.168.12.110:8096 |
| Overseerr | 5055 | http://192.168.12.110:5055 |
| Sonarr | 8989 | http://192.168.12.110:8989 |
| Radarr | 7878 | http://192.168.12.110:7878 |
| Prowlarr | 9696 | http://192.168.12.110:9696 |
| qBittorrent | 9090 | http://192.168.12.110:9090 |
| Bazarr | 6767 | http://192.168.12.110:6767 |
| Traefik Dashboard | 8080 | http://192.168.12.110:8080 |

### Raspberry Pi 3B+ (192.168.12.20)

| Service | Port | URL |
|---------|------|-----|
| AdGuard Home replica | 80 | http://192.168.12.20 |
| DNS replica | 53 | Set as DNS 2 on router |
| wg-easy | 51821 | http://192.168.12.20:51821 |
| WireGuard VPN | 51820/UDP | Forward this port on router to 192.168.12.20 |
| Vaultwarden | 443 | https://192.168.12.20 (via Caddy) |

## WireGuard Remote Access

wg-easy runs on the **Raspberry Pi 3B+** for remote client access.

- Pi listens on port 51820/UDP — forward this port on your router to `192.168.12.20`
- Clients (laptop, Android, Fire TV) import config via wg-easy web UI at `:51821`
- Once connected, all service URLs work as if on LAN

> This is separate from the CT-100/CT-101 WireGuard used to protect qBittorrent traffic.

## AdGuard Home DNS (Primary + Replica)

Two AdGuard Home instances provide redundant network-wide ad blocking with zero downtime:

- **Primary**: CT-102 @ `192.168.12.102` — set as DNS 1 on your router
- **Replica**: Pi 3B+ @ `192.168.12.20` — set as DNS 2 on your router
- **Fallback**: `1.1.1.1` — set as DNS 3 on your router (network never dies)

Sync is handled automatically by `adguardhome-sync` running in CT-102, pushing config to the Pi replica every 5 minutes.

> Test that Jellyfin and streaming services resolve correctly after enabling. Add whitelist entries in AdGuard Home as needed.

## Vaultwarden

Vaultwarden (self-hosted Bitwarden) runs on the Pi behind Caddy for automatic HTTPS.

- Caddy handles TLS — local self-signed cert or real domain with Let's Encrypt
- LAN access: `https://192.168.12.20`
- Remote access: connect via WireGuard first, then use the LAN URL
