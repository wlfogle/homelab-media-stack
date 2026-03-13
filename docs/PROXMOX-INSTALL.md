# Proxmox VE 9.0 — Installation Guide for Tiamat

**Target machine**: Tiamat (CyberPowerPC)
- CPU: AMD Ryzen 5 3600
- RAM: 8 GB DDR4
- GPU: AMD RX 580 (passthrough to VM-200)
- Boot drive: 240 GB SSD → Proxmox OS + containers
- Media drive: 2 TB HDD → /mnt/media (bind-mounted into containers)
- Network: 192.168.12.x (T-Mobile gateway + TP-Link AX-3000 AP)

USB installer was flashed with: `proxmox-ve_9.0-1.iso`

---

## Part 1 — BIOS Setup

Boot into BIOS (Delete or F2 on CyberPowerPC).

### Required changes

| Setting | Location | Value |
|---------|----------|-------|
| AMD-Vi / IOMMU | Advanced → CPU Config | **Enabled** |
| SVM Mode (virtualization) | Advanced → CPU Config | **Enabled** |
| Boot order | Boot | USB first, then SSD |
| CSM / Legacy boot | Boot | **Disabled** (UEFI only) |
| Fast Boot | Boot | **Disabled** |
| Secure Boot | Security | **Disabled** |

> IOMMU is required for RX 580 GPU passthrough to VM-200 (Windows/PlayOn).

Save and exit — machine will reboot to USB installer.

---

## Part 2 — Proxmox Installer

### 2.1 Boot menu
- Select **Install Proxmox VE (Graphical)**
- Accept EULA

### 2.2 Target disk
- Select the **240 GB SSD** (e.g. `/dev/sda`)
- Filesystem: **ext4** (default — simpler than ZFS on 8GB RAM)
- **Do NOT select the 2 TB HDD** — that is reserved for media

> If you want ZFS: use `zfs (RAID0)` on the 240GB SSD only.
> ZFS ARC cache will consume RAM aggressively — with only 8GB, stick with ext4.

### 2.3 Location & timezone
- Country: United States
- Timezone: your local zone (e.g. America/New_York)
- Keyboard: en-US

### 2.4 Admin password & email
- Set a strong root password — you'll use this for all `pct exec` / `qm` commands
- Email: any (used for system alerts)

### 2.5 Network configuration
| Field | Value |
|-------|-------|
| Management interface | select your ethernet NIC (e.g. `enp6s0`) |
| Hostname | `tiamat.local` |
| IP address | `192.168.12.50/24` |
| Gateway | `192.168.12.1` |
| DNS server | `192.168.12.1` |

> After everything is running, DNS will switch to `192.168.12.102` (AdGuard Home CT-102).

### 2.6 Finish install
- Review summary, click **Install**
- Installation takes ~5 minutes
- **Remove USB when prompted**, then press Enter to reboot

---

## Part 3 — First Boot & Post-Install

### 3.1 Access web UI
On any device on the 192.168.12.x network:
```
https://192.168.12.50:8006
```
Login: `root` / (password you set)
Accept the self-signed cert warning.

### 3.2 Disable subscription nag (community repo)

SSH into Tiamat or use the Proxmox web shell:
```bash
# Replace enterprise repo with no-subscription community repo
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-community.list
rm -f /etc/apt/sources.list.d/pve-enterprise.list

# Disable Ceph repo (not using it)
rm -f /etc/apt/sources.list.d/ceph.list

apt update && apt dist-upgrade -y
```

### 3.3 Set up 2 TB HDD for media

```bash
# Check disk path (look for ~2TB disk, e.g. /dev/sdb)
lsblk

# Partition the 2TB HDD (if fresh/unformatted)
parted /dev/sdb --script mklabel gpt mkpart primary ext4 0% 100%

# Format
mkfs.ext4 -L media /dev/sdb1

# Mount permanently
mkdir -p /mnt/media /mnt/downloads
echo "LABEL=media /mnt/media ext4 defaults,nofail 0 2" >> /etc/fstab
mkdir -p /mnt/media/{movies,tv,music,books,playon,downloads}
mount -a

# Verify
df -h /mnt/media
```

### 3.4 Download LXC templates

```bash
pveam update
pveam download local debian-12-standard_12.7-1_amd64.tar.zst
pveam download local alpine-3.19-default_20240207_amd64.tar.xz
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst
```

---

## Part 4 — Run Setup Scripts

Clone the repo and run the automated scripts:

```bash
apt install -y git
git clone https://github.com/wlfogle/homelab-media-stack.git /opt/homelab-media-stack
cd /opt/homelab-media-stack

# 1. Post-install Proxmox host config (IOMMU, dirs, templates)
chmod +x scripts/setup-proxmox.sh
./scripts/setup-proxmox.sh

# 2. Create all LXC containers + deploy media stack
chmod +x scripts/deploy-media-stack.sh
./scripts/deploy-media-stack.sh
```

`deploy-media-stack.sh` creates:
| ID | Hostname | IP | Purpose |
|----|----------|----|---------|
| CT-100 | wg-server | 192.168.12.100 | WireGuard VPN server |
| CT-101 | gluetun-proxy | 192.168.12.101 | TinyProxy → WireGuard (qBit kill-switch) |
| CT-102 | adguardhome | 192.168.12.102 | AdGuard Home DNS |
| CT-110 | media-stack | 192.168.12.110 | Jellyfin, Plex, Sonarr, Radarr, etc. |
| CT-150 | firetv-controller | 192.168.12.150 | ADB controller for Fire TVs |

VM-200 (Windows 10 for PlayOn Desktop) is created manually — see `proxmox/vm-windows-playon.md`.

---

## Part 5 — Post-Deploy Configuration

### 5.1 Edit the media stack .env file

```bash
pct exec 110 -- bash -c "nano /opt/homelab-media-stack/media-stack/.env"
```

Required values to set:
```
PLEX_CLAIM=claim-xxxxxxxxxxxx   # get from https://plex.tv/claim
TZ=America/New_York
DUCKDNS_TOKEN=your-token-here
```

Get your Plex claim token at: https://plex.tv/claim (expires in 4 minutes — do this right before first `docker compose up`)

### 5.2 WireGuard VPN server (CT-100)

```bash
pct exec 100 -- ash
# Inside CT-100:
apk add wireguard-tools
# Generate server keys, configure wg0 interface
# See infrastructure/wireguard-server/ for full config
```

### 5.3 Set DNS to AdGuard Home

Once CT-102 is running and AdGuard Home is configured at http://192.168.12.102:3000:

In your router (T-Mobile gateway at 192.168.12.1):
- Primary DNS: `192.168.12.102` (CT-102 AdGuard Home)
- Secondary DNS: `192.168.12.20` (Pi 3B+ AdGuard replica — once Pi is set up)
- Tertiary DNS: `1.1.1.1` (fallback)

Or set per-device in each client's network settings.

### 5.4 DuckDNS dynamic DNS

```bash
chmod +x /opt/homelab-media-stack/scripts/setup-duckdns.sh
/opt/homelab-media-stack/scripts/setup-duckdns.sh
# Domain: lou-fogle-media-stack.duckdns.org
```

### 5.5 Sideload TiamatsStack APK to Fire TVs

On each Fire TV before running the script:
1. Settings → My Fire TV → Developer Options → **ADB Debugging: ON**
2. Settings → My Fire TV → Developer Options → **Apps from Unknown Sources: ON**
3. Note the IP address shown in Settings → My Fire TV → About → Network

Then from your laptop/PC (with Android Studio or android-tools-adb installed):
```bash
cd /opt/homelab-media-stack/android-app
./build-app.sh install-firetv
# Sideloads to 192.168.12.51, .52, .53 automatically
```

---

## Part 6 — Service URLs (all working)

| Service | URL | Credentials |
|---------|-----|-------------|
| **Proxmox Web UI** | https://192.168.12.50:8006 | root / (your password) |
| **Homarr** | http://192.168.12.110:7575 | set on first run |
| **Jellyfin** | http://192.168.12.110:8096 | set on first run |
| **Plex** | http://192.168.12.110:32400/web | plex.tv account |
| **Overseerr** | http://192.168.12.110:5055 | set on first run |
| **Sonarr** | http://192.168.12.110:8989 | none (local) |
| **Radarr** | http://192.168.12.110:7878 | none (local) |
| **Prowlarr** | http://192.168.12.110:9696 | none (local) |
| **qBittorrent** | http://192.168.12.110:9090 | admin / adminadmin (change!) |
| **Bazarr** | http://192.168.12.110:6767 | none (local) |
| **Tautulli** | http://192.168.12.110:8181 | set on first run |
| **AdGuard Home** | http://192.168.12.102:3000 | set on first run |
| **Fire TV Controller** | http://192.168.12.150:5000 | none (LAN only) |

---

## Part 7 — GPU Passthrough for VM-200 (RX 580)

> Only needed once VM-200 (Windows 10 / PlayOn Desktop) is set up.

### 7.1 Verify IOMMU groups

```bash
# Run on Proxmox host — RX 580 should appear in its own group
for d in /sys/kernel/iommu_groups/*/devices/*; do
  n=${d#*/iommu_groups/*}; n=${n%%/*}
  printf 'IOMMU Group %s ' "$n"
  lspci -nns "${d##*/}"
done | grep -i "AMD\|Radeon\|RX 580"
```

### 7.2 Blacklist AMD GPU on host

```bash
echo "blacklist amdgpu" >> /etc/modprobe.d/blacklist.conf
echo "blacklist radeon" >> /etc/modprobe.d/blacklist.conf
echo "options vfio-pci ids=1002:687f,1002:aaf8" >> /etc/modprobe.d/vfio.conf
update-initramfs -u
reboot
```

> GPU IDs above are for RX 580. Verify yours with `lspci -nn | grep -i radeon`.
> After reboot, the GPU will be claimed by VFIO and unavailable to Proxmox host — that's correct.

### 7.3 Add GPU to VM-200

In Proxmox web UI → VM-200 → Hardware → Add → PCI Device → select RX 580
Check: **All Functions**, **ROM-Bar**, **PCI-Express**

See `proxmox/vm-windows-playon.md` for full Windows 10 VM setup.

---

## Troubleshooting

**Can't reach web UI after install**
- Confirm Tiamat ethernet is plugged in to the TP-Link AP or T-Mobile gateway
- Check IP: connect monitor/keyboard to Tiamat, login as root, run `ip a`

**Container won't start**
```bash
pct start <CTID>
journalctl -u pve-container@<CTID> --no-pager
```

**Plex can't find HDHomeRun**
- Plex must use `network_mode: host` — verify in media-stack/docker-compose.yml
- HDHomeRun must be on same subnet (192.168.12.x) — it should be if plugged into TP-Link AP

**qBittorrent traffic not going through VPN**
```bash
# Check proxy connectivity from CT-110
pct exec 110 -- curl -x http://192.168.12.101:8888 https://icanhazip.com
# Should return WireGuard exit IP, NOT your T-Mobile IP
```

**Containers lose network after reboot**
```bash
# Ensure containers are set to start on boot
pct set <CTID> --onboot 1
```
