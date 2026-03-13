# VM-200: Windows 10 + PlayOn Desktop

## Purpose
Keeps your **PlayOn Desktop lifetime subscription alive** after migrating Tiamat to Proxmox.
PlayOn Desktop is Windows-only — this VM virtualizes your existing Windows 10 install
so it keeps running 24/7 and saves recordings directly to `/mnt/media/playon` on the
Proxmox host, which Plex and Jellyfin both watch automatically.

## VM Specs

| Setting | Value |
|---------|-------|
| **VM ID** | 200 |
| **IP** | 192.168.12.200 |
| **CPU** | 4 cores (Ryzen 5 3600 has 6 cores — leave 2 for host/containers) |
| **RAM** | 4096 MB |
| **Disk** | 60GB (virtio, on local-lvm SSD) |
| **OS** | Windows 10 Home (your existing license) |
| **Network** | vmbr0, VirtIO NIC |
| **Display** | VNC or SPICE |

## Create the VM on Proxmox

```bash
# Create Windows VM
qm create 200 \
  --name windows-playon \
  --memory 4096 \
  --cores 4 \
  --net0 virtio,bridge=vmbr0,firewall=1 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:60 \
  --ide2 local:iso/Win10.iso,media=cdrom \
  --ide3 local:iso/virtio-win.iso,media=cdrom \
  --boot order=ide2 \
  --ostype win10 \
  --cpu host \
  --machine q35 \
  --onboot 1

# Start it
qm start 200
```

> Download VirtIO drivers ISO: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

## Windows 10 Installation

1. Connect via Proxmox web console (SPICE or VNC)
2. Install Windows 10 — use your existing product key
3. During install, load VirtIO storage driver from the second ISO when disk isn't found
4. After install, install all VirtIO drivers from the ISO
5. Enable Remote Desktop for headless management

## Shared Folder Setup

Mount `/mnt/media/playon` from Proxmox host into the Windows VM so PlayOn saves
recordings directly to the media share.

### Option A — VirtIO-FS (recommended, fastest)
```bash
# On Proxmox host, add shared folder to VM config
cat >> /etc/pve/qemu-server/200.conf <<EOF
virtiofs0: /mnt/media/playon,cache=none
EOF

qm reboot 200
```
In Windows: install WinFSP, then map `\\wsl$\virtiofs\` or use the VirtIO-FS driver.

### Option B — Samba share (simpler)
```bash
# On Proxmox host, install Samba
apt install -y samba

cat >> /etc/samba/smb.conf <<EOF
[playon]
   path = /mnt/media/playon
   browsable = yes
   writable = yes
   guest ok = yes
   create mask = 0664
   directory mask = 0775
EOF

systemctl restart smbd
```
In Windows: Map network drive → `\\192.168.12.10\playon`

## PlayOn Desktop Setup

1. Install PlayOn Desktop from https://www.playon.tv
2. Sign in with your lifetime account
3. Settings → Recording → Save Location → set to the mapped drive (`Z:\` or `\\192.168.12.10\playon`)
4. Set up your streaming service logins (Netflix, Prime, Disney+, etc.)
5. Schedule recordings or record on-demand

## Plex + Jellyfin Auto-Scan

Both Plex and Jellyfin in CT-110 have `/mnt/media/playon` mounted read-only.

**Plex**: Add library → Other Videos → `/playon`
**Jellyfin**: Dashboard → Libraries → Add → set content type to Movies or Shows → `/data/playon`

New recordings appear automatically within minutes of PlayOn finishing.

## Auto-Start on Boot

The VM has `onboot=1` set — it starts automatically with Proxmox.
PlayOn Desktop needs to be configured to launch on Windows login:

1. Press `Win+R` → `shell:startup`
2. Create a shortcut to PlayOn Desktop in the Startup folder

## Resource Notes

- 8GB RAM on Tiamat is tight with 4 containers + 1 VM
- **Strongly recommend adding 8-16GB RAM** before running VM-200 alongside full media stack
- Minimum viable: start VM-200 only when you need to schedule recordings, then shut it down
- Ideal: 16-32GB RAM → VM-200 + all containers running 24/7

## Management

```bash
# Start/stop VM
qm start 200
qm stop 200
qm shutdown 200   # graceful Windows shutdown

# Check status
qm status 200

# Connect to console
# Proxmox web UI → VM 200 → Console
```
