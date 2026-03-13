# Networking

## LAN Layout

```
Router (192.168.12.1)
├── Desktop Server (Proxmox)  → 192.168.12.10  (static)
├── Tiamat                    → 192.168.12.242 (existing)
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

| Service | Port | URL |
|---------|------|-----|
| Proxmox Web UI | 8006 | https://192.168.12.10:8006 |
| Traefik Dashboard | 8080 | http://192.168.12.10:8080 |
| Jellyfin | 8096 | http://192.168.12.10:8096 |
| Sonarr | 8989 | http://192.168.12.10:8989 |
| Radarr | 7878 | http://192.168.12.10:7878 |
| qBittorrent | 8080 | http://192.168.12.10:8080 |
| Overseerr | 5055 | http://192.168.12.10:5055 |
| Pi-hole | 80 | http://192.168.12.10/admin |
| Grafana | 3000 | http://192.168.12.10:3000 |
| WireGuard | 51820/UDP | VPN access |

## WireGuard Remote Access

WireGuard VPN allows secure access to all services from outside the LAN without exposing individual ports.

- Server listens on port 51820/UDP
- Clients (laptop, tablet, phone) connect via WireGuard app
- Once connected, all service URLs work as if on LAN

## Pi-hole DNS

After deploying Pi-hole, set your router's DNS to point to the server IP.
All LAN devices will automatically use Pi-hole for ad/tracker blocking.

> **Important:** Test that Plex/Jellyfin and streaming services still resolve correctly after enabling Pi-hole. Add whitelist entries as needed.
