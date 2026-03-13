#!/bin/bash
# ============================================================
# Deploy Full Media Stack to Proxmox LXC
# Creates containers for: media stack, AdGuard Home, WireGuard VPN
# Run on Proxmox host as root after setup-proxmox.sh
# ============================================================
set -e

DEBIAN_TEMPLATE=$(pveam list local | grep debian-12 | awk '{print $1}' | head -1)
if [ -z "$DEBIAN_TEMPLATE" ]; then
  echo "==> Downloading Debian 12 template..."
  pveam update
  pveam download local debian-12-standard_12.7-1_amd64.tar.zst
  DEBIAN_TEMPLATE=$(pveam list local | grep debian-12 | awk '{print $1}' | head -1)
fi

echo "==> Using template: $DEBIAN_TEMPLATE"

# ── CT-100: WireGuard Server ─────────────────────────────
echo "==> Creating CT-100 (WireGuard Server)..."
pct create 100 local:vztmpl/alpine-3.19-default_20240207_amd64.tar.xz \
  --hostname wg-server \
  --memory 256 --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.12.100/24,gw=192.168.12.1 \
  --storage local-lvm --rootfs local-lvm:4 \
  --unprivileged 0 --features nesting=1 \
  --onboot 1

# Add TUN device access
cat >> /etc/pve/lxc/100.conf <<EOF
lxc.cgroup.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net dev/net none bind,create=dir
EOF

# ── CT-101: Gluetun Proxy ───────────────────────────────
echo "==> Creating CT-101 (Gluetun/TinyProxy)..."
pct create 101 local:vztmpl/alpine-3.19-default_20240207_amd64.tar.xz \
  --hostname gluetun-proxy \
  --memory 256 --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.12.101/24,gw=192.168.12.1 \
  --storage local-lvm --rootfs local-lvm:4 \
  --unprivileged 0 --features nesting=1,keyctl=1 \
  --onboot 1

cat >> /etc/pve/lxc/101.conf <<EOF
lxc.cgroup.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net dev/net none bind,create=dir
lxc.apparmor.profile: unconfined
lxc.mount.auto: proc:rw sys:rw
EOF

# ── CT-102: AdGuard Home ────────────────────────────────
echo "==> Creating CT-102 (AdGuard Home)..."
pct create 102 $DEBIAN_TEMPLATE \
  --hostname adguardhome \
  --memory 512 --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.12.102/24,gw=192.168.12.1 \
  --storage local-lvm --rootfs local-lvm:8 \
  --unprivileged 1 --features nesting=1 \
  --onboot 1

# ── CT-110: Media Stack ─────────────────────────────────
echo "==> Creating CT-110 (Media Stack)..."
pct create 110 $DEBIAN_TEMPLATE \
  --hostname media-stack \
  --memory 4096 --cores 4 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.12.110/24,gw=192.168.12.1 \
  --storage local-lvm --rootfs local-lvm:32 \
  --unprivileged 1 --features nesting=1 \
  --onboot 1

# Bind mount media and downloads from host
cat >> /etc/pve/lxc/110.conf <<EOF
mp0: /mnt/media,mp=/mnt/media
mp1: /mnt/downloads,mp=/mnt/downloads
mp2: /opt/appdata,mp=/opt/appdata
lxc.cgroup.devices.allow: c 226:0 rwm
lxc.cgroup.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
EOF

echo "==> Starting containers..."
pct start 100
pct start 101
pct start 102
pct start 110

sleep 5

echo "==> Installing Docker in CT-102 (AdGuard Home)..."
pct exec 102 -- bash -c "apt update && apt install -y curl && curl -fsSL https://get.docker.com | sh"

echo "==> Installing Docker in CT-110 (Media Stack)..."
pct exec 110 -- bash -c "apt update && apt install -y curl git && curl -fsSL https://get.docker.com | sh"

echo "==> Cloning repo into CT-110..."
pct exec 110 -- bash -c "git clone https://github.com/wlfogle/homelab-media-stack.git /opt/homelab-media-stack"

echo "==> Deploying media stack in CT-110..."
pct exec 110 -- bash -c "cp /opt/homelab-media-stack/media-stack/.env.example /opt/homelab-media-stack/media-stack/.env && cd /opt/homelab-media-stack/media-stack && docker compose up -d"

echo ""
echo "=== Media Stack Deployed ==="
echo ""
echo "Container IPs:"
echo "  CT-100 (WireGuard Server):  192.168.12.100"
echo "  CT-101 (Gluetun Proxy):     192.168.12.101"
echo "  CT-102 (AdGuard Home):      192.168.12.102 → http://192.168.12.102:3000 (setup)"
echo "  CT-110 (Media Stack):       192.168.12.110"
echo ""
echo "Media services accessible at 192.168.12.110:"
echo "  Jellyfin:    :8096"
echo "  Sonarr:      :8989"
echo "  Radarr:      :7878"
echo "  Prowlarr:    :9696"
echo "  qBittorrent: :9090"
echo "  Overseerr:   :5055"
echo ""
echo "Next: Run setup-wg-server.sh in CT-100 to configure VPN"
