# Homelab Media Stack Optimization Plan

A working runbook for the **actual** homelab, not a generic template. Every
phase targets real hardware and real services already deployed. Aspirational
copy, multi-model AI ensembles, vector memory palaces, and predictive scalers
from earlier drafts have been removed.

## Inventory (authoritative)

| Node     | Hardware                                           | Role                                                                      |
|----------|----------------------------------------------------|---------------------------------------------------------------------------|
| Tiamat   | AMD Ryzen 5 3600 · 32 GB DDR4-3200 · RX 580 4 GB · 2 TB HDD + 240 GB SSD | Proxmox VE host; 27 LXCs + 3 VMs (VM-500 HAOS, VM-901 Windows-Gaming, VM-200 Alexa-Bridge) |
| Laptop   | Intel i9-13900HX · 62 GB DDR5 · RTX 4080 (laptop)  | Primary admin workstation, dev, Android APK builds, **Ollama @ :11434 (41 models)** |
| Bahamut  | Raspberry Pi 4 (DietPi) @ 192.168.12.244           | Edge DNS (AdGuard), reverse proxy (Caddy + DuckDNS), WireGuard mgmt (wg-easy), Vaultwarden replica, Tailscale |
| Ziggy    | CT-900 (LXC on Tiamat)                             | Open WebUI :3000 + SearXNG :8081 (front-end for laptop Ollama)            |

Bahamut is the Pi 4 at `.244`. Ziggy is a container on Tiamat. Older docs
that used "Ziggy" as the Pi are stale.

## Optimization targets

Tracked, measurable, and modest:

- **HDD IO wait** on Tiamat `< 10 %` sustained (currently spikes during
  library scans and download moves).
- **Jellyfin HW transcode**: one 1080p → 720p stream `< 25 % CPU` on CT-231
  after VAAPI enablement (CPU transcodes currently run 80-100 %).
- **HAOS recorder** median query time `< 100 ms` after MariaDB migration
  (SQLite on HAOS cannot keep up with HACS-heavy histories).
- **Ollama throughput** on laptop: first-token latency `< 800 ms` for 7B-8B
  Q4 models served to CT-900 Open WebUI.
- **Stack boot**: 10-tier startup order in Proxmox already enforced — verify
  it still ramps cleanly after changes.

No "5-10x" claims. No new AI frameworks introduced.

---

## Phase 1 — Tiamat (Proxmox host)

Everything here runs on the host, not inside a CT. Keep changes reversible
(`/etc/sysctl.d/*`, `/etc/default/grub`), commit to this repo when applied.

### 1.1 CPU governor + scheduler

Ryzen 5 3600 with `acpi-cpufreq`. `intel_pstate` tricks from generic guides
do not apply.

```bash
# Install if missing
apt install -y linux-cpupower

# Set performance governor on all 12 threads
cpupower frequency-set -g performance

# Persist
cat >/etc/systemd/system/cpu-performance.service <<'EOF'
[Unit]
Description=Set CPU governor to performance
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/bin/cpupower frequency-set -g performance
[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now cpu-performance.service
```

Verify: `cpupower frequency-info | grep -i governor`.

### 1.2 Memory

Ryzen IOMMU is already `pt` for VFIO (see `docs/HARDWARE.md`). Remaining
knobs:

```bash
cat >/etc/sysctl.d/10-tiamat-mem.conf <<'EOF'
vm.swappiness = 10
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
vm.vfs_cache_pressure = 50
kernel.numa_balancing = 0     # single-socket, no NUMA
EOF
sysctl --system
```

### 1.3 KSM for LXC dedup

27 LXCs run overlapping userland. KSM dedups anonymous pages:

```bash
# Enable KSM + tuning
echo 1 >/sys/kernel/mm/ksm/run
echo 100 >/sys/kernel/mm/ksm/pages_to_scan
echo 200 >/sys/kernel/mm/ksm/sleep_millisecs

# Persist via ksmtuned
apt install -y ksmtuned
systemctl enable --now ksmtuned
```

Expected gain: 1-3 GB RAM recovered at steady state (watch
`/sys/kernel/mm/ksm/pages_sharing`).

### 1.4 Storage scheduler

2 TB rotating HDD (`sda`, model `ST2000DM008`): `mq-deadline` beats `none`
and `kyber` for mixed read/write on spinners. SSD (`sdb`) is passed through
to VM-901 — leave alone.

```bash
cat >/etc/udev/rules.d/60-scheduler.rules <<'EOF'
ACTION=="add|change", KERNEL=="sda", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
EOF
udevadm control --reload-rules
udevadm trigger
```

### 1.5 Boot order (verify only)

The 10-tier boot order across 27 CTs is already live. Re-verify after any
host kernel upgrade:

```bash
pct list | awk 'NR>1 {print $1}' | while read id; do
  echo "CT-$id startup=$(pct config $id | awk -F': ' '/^startup:/ {print $2}')"
done
```

---

## Phase 2 — Storage (2 TB HDD)

### 2.1 Mount flags

`/mnt/hdd` hosts downloads and libraries. `noatime,nodiratime` reduces write
amplification on rotational media.

```bash
# /etc/fstab (snippet)
/dev/pve/media-hdd  /mnt/hdd  ext4  defaults,noatime,nodiratime  0 2
```

Remount live: `mount -o remount,noatime,nodiratime /mnt/hdd`.

### 2.2 Transcode dirs on tmpfs

Jellyfin (CT-231) and Plex (CT-230) default transcode paths hit the HDD.
Move them to tmpfs on the host, bind-mount into the CT:

```bash
# On Tiamat
mkdir -p /tmp/jellyfin-transcode /tmp/plex-transcode
cat >>/etc/fstab <<'EOF'
tmpfs /tmp/jellyfin-transcode tmpfs defaults,size=4G,uid=100000,gid=100000 0 0
tmpfs /tmp/plex-transcode     tmpfs defaults,size=4G,uid=100000,gid=100000 0 0
EOF
mount -a

# Bind into CT-231 (unprivileged)
pct set 231 -mp0 /tmp/jellyfin-transcode,mp=/config/transcodes
pct set 230 -mp0 /tmp/plex-transcode,mp=/config/transcodes
```

Then in each app's settings, point the transcode temp directory at
`/config/transcodes`. Also reduces disk wear.

### 2.3 SQLite WAL across the *arr stack

Radarr is already WAL (see `docs/TROUBLESHOOTING.md`). Apply to the rest:

```bash
for ct in 214 217 218 221 240; do
  pct exec $ct -- sh -c '
    svc=$(ls /config/*.db 2>/dev/null | head -1)
    [ -n "$svc" ] && sqlite3 "$svc" "PRAGMA journal_mode=WAL;"
  '
done
```

Backup the DB first via the app's built-in backup (Settings → General →
Backup).

### 2.4 File Browser permission hook

Already deployed (see main `README.md`). No change.

### 2.5 Backup cadence

`/mnt/hdd/backups` currently captures snapshots. Schedule daily with
retention:

```bash
# On Tiamat, root crontab
0 3 * * * /opt/homelab-media-stack/scripts/backup-stack.sh --keep 7
```

Reference: `scripts/backup-stack.sh`.

---

## Phase 3 — Network

### 3.1 Host sysctl (sized for 1 GbE, not 100 GbE)

The previous draft suggested 128 MB TCP buffers — that's for multi-gig WANs,
not a 1 GbE home LAN. Reasonable values:

```bash
cat >/etc/sysctl.d/20-tiamat-net.conf <<'EOF'
# BBR + fq pacing
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 1 GbE-sized buffers
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Connection handling
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fastopen = 3
EOF
sysctl --system
```

### 3.2 Traefik (CT-103)

In `infrastructure/traefik/traefik.yml`:

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
    http:
      middlewares:
        - compress@file
        - security-headers@file

http:
  middlewares:
    compress:
      compress: {}
    security-headers:
      headers:
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: no-referrer-when-downgrade

serversTransport:
  forwardingTimeouts:
    dialTimeout: 10s
    responseHeaderTimeout: 30s
```

HTTP/2 is on by default; make sure every route preserves `passHostHeader: true`.

### 3.3 AdGuard on Bahamut

DoT upstreams and a larger cache:

```yaml
# /opt/adguardhome/conf/AdGuardHome.yaml (snippets)
dns:
  upstream_dns:
    - tls://1.1.1.1
    - tls://9.9.9.9
    - tls://dns.quad9.net
  bootstrap_dns:
    - 1.1.1.1
    - 9.9.9.9
  cache_size: 67108864   # 64 MiB
  cache_optimistic: true
  ratelimit: 0
```

Router LAN DNS should be `192.168.12.244` with `1.1.1.1` as fallback.

### 3.4 WireGuard MTU

CT-100 → CT-101 tunnel default MTU 1420 usually works. If qBittorrent sees
stalled TCP through TinyProxy, drop to 1380:

```bash
# CT-100 /etc/wireguard/wg0.conf
[Interface]
MTU = 1380
```

### 3.5 Static ARP (CT-215 Radarr)

Already in place (`ip neigh replace 192.168.12.225 …`); see
`docs/NETWORKING.md`.

---

## Phase 4 — Per-LXC media stack tuning

### 4.1 Jellyfin VAAPI on RX 580 (CT-231)

The RX 580 is currently VFIO-bound for VM-901 passthrough. Two options:

- **Option A — dedicated VAAPI GPU** (recommended if you retire or downgrade
  VM-901 gaming on Tiamat): unbind GPU from VFIO, install
  `libva2 mesa-va-drivers intel-media-va-driver` on CT-231, expose
  `/dev/dri/renderD128` to the CT.
- **Option B — keep VFIO**: leave Jellyfin on CPU transcode (current).
  Document the CPU ceiling as a known constraint.

If going with Option A:

```bash
# On Tiamat: bind-mount DRI into CT-231 (unprivileged)
pct set 231 -mp1 /dev/dri,mp=/dev/dri
# Inside CT-231
apt install -y vainfo libva2 intel-media-va-driver mesa-va-drivers
vainfo   # should list AMD Radeon (radeonsi)
```

In Jellyfin → Dashboard → Playback → Transcoding:

- Hardware acceleration: `VAAPI`
- VA API device: `/dev/dri/renderD128`
- Enable hardware decoding for: H264, HEVC, VP9
- Enable hardware encoding: yes
- Throttle transcodes: yes

### 4.2 Plex (CT-230)

Plex native transcoder niceness via systemd drop-in:

```bash
# CT-230
mkdir -p /etc/systemd/system/plexmediaserver.service.d
cat >/etc/systemd/system/plexmediaserver.service.d/nice.conf <<'EOF'
[Service]
Nice=5
IOSchedulingClass=best-effort
IOSchedulingPriority=4
EOF
systemctl daemon-reload
systemctl restart plexmediaserver
```

### 4.3 Prowlarr (CT-210)

Sync every 60 min (not 15) to reduce indexer load. In Prowlarr → Settings →
Apps → each *arr → set "Sync Level" = `Add and Remove Only`.

### 4.4 qBittorrent (CT-212)

`Settings → Advanced`:

- Asynchronous I/O threads: `8`
- File pool size: `500`
- Disk cache: `256 MiB`
- Disk cache expiry: `60 s`
- Coalesce reads/writes: `enabled`

### 4.5 RDT-Client (CT-213)

`appsettings.json`:

```json
{
  "Provider": "RealDebrid",
  "DownloadClient": "Internal",
  "ParallelDownloads": 4,
  "ParallelUnpack": 2,
  "ProxyServer": ""
}
```

### 4.6 Bazarr (CT-240)

Settings → Subtitles → Performance: `Adaptive searching` ON, `Upgrade only
recent episodes` ON.

### 4.7 Sonarr/Radarr import workers

`Settings → Media Management → Use Hardlinks` already on. Confirm
`Rescan Series Folder After Refresh = After Manual Refresh` to avoid HDD
thrash during scheduled RSS pulls.

---

## Phase 5 — Laptop AI node (192.168.12.172)

Hardware: i9-13900HX (8P+16E, 32 threads), 62 GB DDR5, RTX 4080 (laptop),
Pop!_OS 22.04 on kernel 6.17.x, 41 Ollama models.

### 5.1 CPU governor

Pop!_OS ships `system76-power`. Set profile for AI throughput:

```bash
system76-power profile performance
```

Battery mode triggers thermal throttling — avoid while running inference.

### 5.2 Ollama environment

`/etc/systemd/system/ollama.service.d/override.conf`:

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_KEEP_ALIVE=30m"
Environment="OLLAMA_NUM_PARALLEL=2"
Environment="OLLAMA_MAX_LOADED_MODELS=2"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
```

Then `systemctl daemon-reload && systemctl restart ollama`.

With 12 GB VRAM on the 4080 (laptop variant), `OLLAMA_MAX_LOADED_MODELS=2`
is the realistic ceiling for 7-8B Q4_K_M models. Go to 1 for 13B+.

### 5.3 CUDA + NVIDIA power mode

```bash
sudo nvidia-smi -pm 1
sudo nvidia-smi --auto-boost-default=0
# Do NOT pin max clocks on a laptop — it will throttle anyway.
```

### 5.4 CT-900 (Open WebUI) → laptop Ollama

Open WebUI's `OLLAMA_BASE_URLS` should be
`http://192.168.12.172:11434`. Verify reachability:

```bash
pct exec 900 -- curl -sS http://192.168.12.172:11434/api/tags | jq '.models | length'
# Expect: 41
```

---

## Phase 6 — Bahamut (Pi 4 DietPi @ 192.168.12.244)

### 6.1 Swap off SD

DietPi ships swap on the SD card. If a USB SSD is attached, migrate:

```bash
dietpi-drive_manager   # move dietpi_swapfile target to /mnt/usb
```

### 6.2 AdGuard already covered in §3.3.

### 6.3 Caddy gzip + TLS cache

```
# /etc/caddy/Caddyfile
{
  email you@example.com
  servers {
    metrics
  }
}
*.duckdns.org {
  encode gzip zstd
  tls { on_demand }
}
```

### 6.4 wg-easy peer expiry

`WG_EASY_ENABLE_EXPIRY=true` in the compose env, default 90 days.

### 6.5 adguardhome-sync

Cron (Bahamut → Ziggy is reversed; Bahamut is the primary DNS).
`infrastructure/adguardhome/adguardhome-sync.yaml` already deployed.

---

## Phase 7 — Home Assistant (VM-500 @ 192.168.12.250)

### 7.1 Recorder → MariaDB on CT-106

SQLite on HAOS caps out quickly with HACS-heavy histories. Point recorder at
the existing PostgreSQL-neighbour CT-106 MariaDB service (add if only
PostgreSQL is running):

```yaml
# /config/configuration.yaml
recorder:
  db_url: mysql://homeassistant:<pw>@192.168.12.106/homeassistant?charset=utf8mb4
  purge_keep_days: 14
  commit_interval: 5
  exclude:
    domains:
      - updater
      - automation
    entity_globs:
      - sensor.*_uptime
      - sensor.*_last_restart
```

Create the DB + user on CT-106 first:

```sql
CREATE DATABASE homeassistant CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'homeassistant'@'%' IDENTIFIED BY '<strong-pw>';
GRANT ALL PRIVILEGES ON homeassistant.* TO 'homeassistant'@'%';
FLUSH PRIVILEGES;
```

### 7.2 Jellyfin DLNA 404 + IPP timeout

Fix per `docs/errors/HA-2026-04-15.md`. Do these **before** the recorder
migration — MariaDB shouldn't inherit the error-heavy history.

### 7.3 Disable unused default integrations

`configuration.yaml` — only load what you actually use; the default set
includes several that run periodic polling even if unused (e.g.
`media_source`, `stream`, `cloud`). Keep `media_source` (Jellyfin needs
it); drop `cloud` unless you use Nabu Casa.

---

## Phase 8 — Monitoring

No AI alerting. Proxmox already exposes per-CT metrics via its built-in
collector; augment with node-level visibility.

### 8.1 node_exporter on each CT

```bash
# One-shot installer, run from Tiamat host
for id in $(pct list | awk 'NR>1 && $2=="running" {print $1}'); do
  pct exec $id -- sh -c '
    command -v node_exporter >/dev/null && exit
    apt-get update -qq
    apt-get install -y -qq prometheus-node-exporter
  '
done
```

### 8.2 Prometheus + Grafana CT

Add a single CT-280 (e.g.) running Prometheus scraping all
`192.168.12.2XX:9100` endpoints plus the Proxmox API via
`pve_exporter`. Grafana linked from Homarr.

Keep retention modest (15 days) — the HDD doesn't need another heavy
workload.

### 8.3 Uptime checks

Existing `scripts/stack-watchdog.sh` already does health checks. No
replacement needed; just keep its systemd timer enabled.

---

## Phase 9 — Rollout timeline and success criteria

Two weeks, not four. Tuning, not a rewrite.

### Week 1

- Day 1 — Phase 1 (host tunables). Reboot Tiamat on owner's say-so.
- Day 2 — Phase 2 (storage). Transcode tmpfs + SQLite WAL in a single
  maintenance window. Verify with `iostat -xz 2`.
- Day 3 — Phase 3 (network). Apply sysctl, push Traefik config, update
  AdGuard upstreams.
- Day 4-5 — Phase 4 (per-CT media tuning). Start with Prowlarr + qBittorrent
  (low risk), end with Jellyfin VAAPI (only if Option A chosen).

### Week 2

- Day 6 — Phase 5 (laptop Ollama env). Restart service, re-baseline
  tok/s with `ollama run llama3.1:8b "hello"` and a 500-token prompt.
- Day 7 — Phase 6 (Bahamut). Low-risk housekeeping.
- Day 8-9 — Phase 7 (HAOS). Fix Jellyfin DLNA + IPP first, then recorder
  migration.
- Day 10 — Phase 8 (monitoring). Prometheus + Grafana stand-up.
- Day 11-14 — Observe, adjust, document what actually moved.

### Success criteria

Re-measured at end of week 2:

- HDD IO wait sustained `< 10 %` during a library scan.
- One 1080p→720p Jellyfin stream `< 25 %` CPU (if VAAPI enabled).
- HAOS recorder history page loads `< 2 s` on the default dashboard.
- Ollama first-token `< 800 ms` for `llama3.1:8b-instruct-q4_K_M`.
- No `Unknown error (unknown_error)` in HAOS log for 24 h.

If any target misses, revert the specific change — every edit above is
reversible via the files it touches.

---

## What this plan deliberately does **not** do

- No custom AI runtime, vector DB, or multi-model ensemble.
- No kernel rebuilds, custom schedulers, or distro swap.
- No BIOS flash, no reboot without approval, no changes to VM-901
  (Windows/gaming) or to the Jellyfin CT beyond the documented setting
  flips.
- No change to the existing `next.md`, `Check these out.md`, or the
  scratch files in the repo root.
