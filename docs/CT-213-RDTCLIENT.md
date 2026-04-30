# CT-213 — RDT-Client (Real-Debrid downloader)
> Last rebuilt: 2026-04-25. Default download client for Sonarr (TV) and Radarr (movies).
> qBittorrent (CT-212) is the secondary/backup client for books/music/comics.
## Identity
| Field | Value |
|---|---|
| CTID | 213 |
| Hostname | `rdtclient` (was `decypharr` before 2026-04-25) |
| MAC | `BC:24:11:8B:4C:8B` |
| IP | `192.168.12.213/24` |
| Web UI | `http://192.168.12.213:6500` |
| Admin login | `admin / Rdtclient2026!` |
| API impl | qBittorrent-compatible (`/api/v2/...`) — Sonarr/Radarr connect as a "QBittorrent" download client |
| Service | `rdtclient.service` (systemd, native — not Docker) |
| Runtime | .NET 10 aspnetcore (`/usr/share/dotnet/`) — required by RDT-Client v2.0.129+ |
## Storage layout (the important part)
The container is split between two storage tiers:
| Path inside CT | Backing store on host | Why |
|---|---|---|
| `/` (rootfs) | `local-lvm:vm-213-disk-0` (SSD, 8 GB) | App + .NET runtime — fast random I/O |
| `/data` (mp0) | `/mnt/hdd` (2 TB HDD) | Downloads + DB + logs — large sequential I/O |
The SQLite DB (containing the Real-Debrid token, settings, and download history) and the rolling logs both live on the **bind mount**:
```
/data/rdtclient/db/rdtclient.db        (~400 KB)
/data/rdtclient/db/rdtclient.db-shm
/data/rdtclient/db/rdtclient.db-wal
/data/rdtclient/logs/rdtclient.log
```
This is intentional: any future rootfs rebuild leaves the DB intact. The previous default install put everything in `/var/lib/rdtclient` inside the rootfs, which is why the 2026-04-25 incident wiped the visible state.
## appsettings.json
`/opt/rdtclient/appsettings.json` is pinned to point at the bind-mount paths:
```json path=null start=null
{
  "Logging": {
    "File": {
      "Path": "/data/rdtclient/logs/rdtclient.log",
      "FileSizeLimitBytes": 5242880,
      "MaxRollingFiles": 5
    }
  },
  "Database": {
    "Path": "/data/rdtclient/db/rdtclient.db"
  },
  "Port": "6500",
  "BasePath": null
}
```
**Do not change** the `Database.Path` or the new install will create a fresh empty DB.
## Systemd unit
`/etc/systemd/system/rdtclient.service`:
```ini path=null start=null
[Unit]
Description=RdtClient Service
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/rdtclient
ExecStart=/usr/local/bin/dotnet /opt/rdtclient/RdtClient.Web.dll
TimeoutStopSec=20
KillMode=process
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
```
## Wiring in Sonarr / Radarr
Sonarr (`192.168.12.214:8989`) and Radarr (`192.168.12.225:7878`) each have an enabled "QBittorrent"-implementation download client pointed at `192.168.12.213:6500`, priority 1 (qBit at `.212:8080` is priority 2 backup). Sonarr category `sonarr`, Radarr category `radarr`. Test-all returns `isValid=true`.
## Why the rebuild happened (2026-04-25)
1. RDT-Client's rootfs was on `hdd-ct` (a `dir` storage at `/mnt/hdd/ct-storage`), which means `vm-213-disk-0.raw` was a loopback file on the same physical HDD that holds `/data/downloads`.
2. Every container write went through ext4 (in CT) → loop0 → ext4 (host) → HDD. Three journaling layers on one spindle. Sustained iowait of 80 %, load average 40+ on a 12-thread Ryzen.
3. While trying to migrate the rootfs to SSD with `pct move-volume`, the host's `udisks2` daemon kept auto-mounting `loop0` under `/media/root/<uuid>` (it's normally a desktop helper). That conflicting mount made every migration attempt fail mid-way and corrupted the LXC namespace state.
4. The migration interrupt left CT-213 in zombie state — `pct status: running` but `lxc-attach` couldn't get the init PID and even `lo` was DOWN inside.
## Recovery procedure (for reference)
1. `losetup -f -r --show <broken raw>` allocates a fresh read-only loop, mount it to scrape the DB.
2. Copy `/var/lib/rdtclient/rdtclient.db*` out to `/mnt/hdd/rdtclient/db/`.
3. `sqlite3 ... 'PRAGMA wal_checkpoint(TRUNCATE);'` to merge the WAL into the DB so it's portable.
4. `pct destroy 213 --purge 1 --destroy-unreferenced-disks 1 --force 1`.
5. `pct create 213 ... --rootfs local-lvm:8 --mp0 /mnt/hdd,mp=/data ...` (preserves MAC + IP).
6. Install .NET 10 aspnetcore + RDT-Client release zip.
7. Write the appsettings.json above (DB path on bind mount).
8. Write systemd unit, `daemon-reload && enable --now rdtclient`.
The full automation lives in `/home/loufogle/tiamat-rebuild-ct213.sh` (idempotent; safe to re-run if needed).
## Operational notes
- **Real-Debrid token**: stored in the SQLite DB. Do **not** put it in CREDENTIALS.md plaintext (the doc currently has a token, but the live source of truth is the DB).
- **Premium expiration**: `2026-05-19`. Renew before then or downloads stop.
- **Active downloads**: visible in the web UI Torrents tab; also `curl http://192.168.12.213:6500/api/Torrents` after authenticating.
- **Logs**: `/data/rdtclient/logs/rdtclient_*.log` rolling, 5 MB cap each, 5 files.
- **Disk usage**: Downloads land in `/data/downloads/rdtclient/` (HDD). Watch `/mnt/hdd` free space; current 522 GB free.
- **Decypharr**: removed. The host service `rclone-decypharr-rd.service` is stopped/disabled/masked. Do not re-enable; it duplicates RDT-Client's job and doubles RD API hits.
## Health checks
```bash path=null start=null
# from Proxmox host
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://192.168.12.213:6500
lxc-attach -n 213 -- systemctl is-active rdtclient
# Sonarr/Radarr -> RDT-Client
curl -s -X POST "http://192.168.12.214:8989/api/v3/downloadclient/testall" \
    -H "X-Api-Key: $SONARR_KEY" | python3 -m json.tool | head
# DB sanity
ls -la /mnt/hdd/rdtclient/db/
```
## Known gotchas
- RDT-Client v2.0.129+ requires **.NET 10**, not 9. The `dotnet-install.sh --channel 10.0` is what we use; .NET 9 is also kept side-by-side in case of downgrade.
- `udisks2` must stay disabled on the Proxmox host — re-enabling it will resurrect the loop-auto-mount conflicts.
- `loop0`/`loop1` references to `/mnt/hdd/ct-storage/images/{110,213}/...` may persist after this rebuild because the broken `.raw` files were unreferenced after destroy. They harm nothing; clean up with a host reboot when convenient.
- The CT-213 vzdump backup cron should be re-checked — `/mnt/hdd/backups/lxc/` was empty at the time of the incident, so vzdump is either not scheduled, failing silently, or writing elsewhere. Fix this before relying on backup-restore as a recovery path.
