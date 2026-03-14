#!/bin/bash
# =============================================================================
# Ziggy (Raspberry Pi 3B+) — First Boot Setup
# Injected into /boot/firmware/ by setup-sd.sh or Pi Imager advanced settings.
# Runs once on first boot as root, then deletes itself.
#
# What this configures:
#   - Hostname: ziggy
#   - Static IP: 192.168.12.20 (via dhcpcd)
#   - SSH enabled, authorized key pre-loaded (lou-laptop)
#   - Timezone: America/New_York
#   - Installs: git, docker, python3-pip, curl, avahi-daemon
#   - Clones homelab repo + runs pi/setup-pi.sh
# =============================================================================
set -e
exec > /var/log/firstrun.log 2>&1
echo "[firstrun] Started: $(date)"

# ── Hostname ─────────────────────────────────────────────────────────────────
hostnamectl set-hostname ziggy
echo "ziggy" > /etc/hostname
sed -i 's/127\.0\.1\.1.*/127.0.1.1\tziggy/' /etc/hosts
echo "[firstrun] Hostname: ziggy"

# ── Timezone ─────────────────────────────────────────────────────────────────
timedatectl set-timezone America/New_York
echo "[firstrun] Timezone: America/New_York"

# ── Static IP 192.168.12.20 via dhcpcd ───────────────────────────────────────
cat >> /etc/dhcpcd.conf <<'DHCP'

# Ziggy static LAN IP
interface eth0
static ip_address=192.168.12.20/24
static routers=192.168.12.1
static domain_name_servers=192.168.12.1 1.1.1.1
DHCP
echo "[firstrun] Static IP configured: 192.168.12.20"

# ── SSH: enable + inject authorized key ──────────────────────────────────────
systemctl enable ssh
systemctl start ssh || true

PI_HOME="/home/pi"
mkdir -p "$PI_HOME/.ssh"
chmod 700 "$PI_HOME/.ssh"
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF9Xpe5VzjPO6i6DfAZuJP/qCrBcEYwvm23DLAJgTUPS loufogle@pop-os" \
  >> "$PI_HOME/.ssh/authorized_keys"
chmod 600 "$PI_HOME/.ssh/authorized_keys"
chown -R pi:pi "$PI_HOME/.ssh"
echo "[firstrun] SSH authorized key installed"

# ── avahi-daemon (so ziggy.local works on LAN) ────────────────────────────────
apt-get install -y avahi-daemon
systemctl enable avahi-daemon
echo "[firstrun] avahi-daemon installed (ziggy.local mDNS)"

# ── System update + packages ─────────────────────────────────────────────────
echo "[firstrun] Running apt update..."
apt-get update -qq
apt-get install -y git curl python3 python3-pip ca-certificates gnupg lsb-release

# ── Docker ───────────────────────────────────────────────────────────────────
echo "[firstrun] Installing Docker..."
curl -fsSL https://get.docker.com | sh
usermod -aG docker pi
echo "[firstrun] Docker installed"

# ── Clone homelab repo + run Pi setup ────────────────────────────────────────
echo "[firstrun] Cloning homelab repo..."
git clone https://github.com/wlfogle/homelab-media-stack.git /opt/homelab-media-stack
chmod +x /opt/homelab-media-stack/pi/setup-pi.sh

echo "[firstrun] Running pi/setup-pi.sh..."
bash /opt/homelab-media-stack/pi/setup-pi.sh >> /var/log/firstrun.log 2>&1

# ── Cleanup ──────────────────────────────────────────────────────────────────
# Remove this script from rc.local (added by setup-sd.sh)
sed -i '/firstrun\.sh/d' /etc/rc.local

echo "[firstrun] Complete: $(date)"
echo "[firstrun] Log: /var/log/firstrun.log"
echo "[firstrun] Rebooting in 5s to apply static IP..."
sleep 5
reboot
