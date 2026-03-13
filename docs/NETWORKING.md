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
| Traefik Dashboard | 8080 | http://192.168.12.10:8080 |
| Jellyfin | 8096 | http://192.168.12.10:8096 |
| Sonarr | 8989 | http://192.168.12.10:8989 |
| Radarr | 7878 | http://192.168.12.10:7878 |
| qBittorrent | 9090 | http://192.168.12.10:9090 |
| Overseerr | 5055 | http://192.168.12.10:5055 |
| Pi-hole (secondary) | 80 | http://192.168.12.10/admin |
| Grafana | 3000 | http://192.168.12.10:3000 |

### Raspberry Pi 3B+ (192.168.12.20)

| Service | Port | URL |
|---------|------|-----|
| Pi-hole (primary) | 80 | http://192.168.12.20/admin |
| WireGuard | 51820/UDP | VPN — router must forward to Pi |
| Vaultwarden | 443 | https://192.168.12.20 (via Caddy) |

## WireGuard Remote Access

WireGuard runs on the **Raspberry Pi 3B+**, not the Proxmox host.

- Pi listens on port 51820/UDP — forward this port on your router to `192.168.12.20`
- Clients (laptop, tablet, phone) connect via the WireGuard app
- Once connected, all service URLs (Proxmox, Jellyfin, Vaultwarden, etc.) work as if on LAN

## Pi-hole DNS (Primary + Secondary)

Two Pi-hole instances provide redundant DNS:

- **Primary**: Raspberry Pi @ `192.168.12.20` — set as DNS 1 on your router
- **Secondary**: Proxmox LXC @ `192.168.12.10` — set as DNS 2 on your router

Use [Gravity Sync](https://github.com/vmstan/gravity-sync) to keep blocklists and settings in sync between both instances.

> **Important:** Test that Jellyfin and streaming services still resolve correctly after enabling Pi-hole. Add whitelist entries as needed.

## Vaultwarden

Vaultwarden (self-hosted Bitwarden) runs on the Pi behind Caddy for automatic HTTPS.

- Caddy handles TLS — either via a local self-signed cert or a real domain with Let's Encrypt
- LAN access: `https://192.168.12.20`
- Remote access: connect via WireGuard first, then use the LAN URL (no port forwarding needed for Vaultwarden)
