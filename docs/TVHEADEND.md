# TVHeadend + HDHomeRun Live TV Setup

Live OTA TV via HDHomeRun CONNECT tuner, served through TVHeadend DVR
on the laptop and Tiamat (CT-236), with Jellyfin and TVHPlayer clients.

## Architecture

```
HDHomeRun CONNECT (192.168.12.215)
        │ MPEG-TS over HTTP / UDP
        ▼
┌───────────────────────────┐     ┌──────────────────────────────┐
│  Laptop TVHeadend (snap)  │     │  Tiamat CT-236 TVHeadend     │
│  http://192.168.12.172:9981│     │  http://192.168.12.236:9981  │
│  HTSP: :9982              │     │  HTSP: :9982                 │
└───────────┬───────────────┘     └─────────────┬────────────────┘
            │ HTSP / M3U / XMLTV                │ HTSP / M3U / XMLTV
            ▼                                   ▼
┌───────────────────────────────────────────────────────────┐
│              Jellyfin CT-231 (192.168.12.231:8096)        │
│  Live TV ← HDHomeRun native tuner + XMLTV EPG from TVH   │
└───────────────────────────────────────────────────────────┘
            │
            ▼
   TVHPlayer (laptop Flatpak)  ─── http://192.168.12.172:9981
```

## HDHomeRun Device

| Field | Value |
|---|---|
| Model | HDHomeRun CONNECT |
| IP | 192.168.12.215 |
| Device ID | 1048EEE4 |
| Firmware | 20260313 (latest) |
| Tuners | 2 concurrent streams |
| Channels | 46 OTA (Louisville, KY area) |
| Lineup URL | http://192.168.12.215:5004/lineup.m3u |
| Discovery | http://192.168.12.215/discover.json |

### Useful HDHomeRun commands (laptop)

```bash
# Discover device on LAN
hdhomerun_config discover

# List channels
hdhomerun_config 1048EEE4 get /lineup/programs

# Check firmware
hdhomerun_config 1048EEE4 get /sys/version

# Update firmware
hdhomerun_config 1048EEE4 upgrade http://192.168.12.215:80/upgrade

# Stream channel to stdout (test)
hdhomerun_config 1048EEE4 save /tuner0 - | ffplay -i -
```

---

## Laptop TVHeadend (snap)

Installed as a snap (`tvheadend` v4.2.8), runs as a system service.

| | |
|---|---|
| Web UI | http://192.168.12.172:9981 |
| HTSP | 192.168.12.172:9982 |
| M3U | http://192.168.12.172:9981/playlist/channels.m3u |
| XMLTV | http://192.168.12.172:9981/xmltv/channels |
| Auth | None (open LAN access) |
| Config | /var/snap/tvheadend/216/ |

### Status

```bash
systemctl status snap.tvheadend.tvheadend.service
journalctl -u snap.tvheadend.tvheadend.service -f
```

### IPTV Network

- **Network name**: HDHomeRun CONNECT
- **M3U URL**: http://192.168.12.172:8765/hdhomerun.m3u  (local HTTP server)
- **Muxes**: 46  |  **Services**: 46  |  **Channels**: 46
- Max streams: 1 (prevents tuner overload)

### M3U HTTP Server (systemd)

A systemd user service regenerates the HDHomeRun lineup and serves it on port 8765.

```bash
# Check status
systemctl --user status hdhomerun-lineup.service

# Regenerate playlist manually
/usr/local/bin/hdhomerun_config 1048EEE4 get /lineup/programs > ~/hdhomerun.m3u

# Restart server
systemctl --user restart hdhomerun-lineup.service
```

### Re-map channels after rescan

```bash
# Get all service UUIDs
SVCS=$(curl -s http://localhost:9981/api/service/list?enum=1 \
  | python3 -c "import sys,json; print(','.join(e['key'] for e in json.load(sys.stdin)['entries']))")

# Map services → channels
curl -s -X POST http://localhost:9981/api/service/mapper/save \
  -d "node={\"services\":[$(echo $SVCS | sed 's/,/\",\"/g; s/^/\"/; s/$/\"/')],\
\"check_availability\":false,\"encrypted\":true,\"merge_same_name\":true}"
```

---

## Tiamat CT-236 TVHeadend

Deploy with the automated script from the Proxmox host:

```bash
# Run on Proxmox (192.168.12.242)
bash /path/to/homelab-media-stack/scripts/deploy-tvheadend.sh
```

The script:
1. Creates Debian 12 LXC (CT-236, 192.168.12.236)
2. Builds `hdhomerun_config` from SiliconDust source
3. Installs TVHeadend from Cloudsmith repo
4. Configures open LAN access (no login required)
5. Creates HDHomeRun IPTV auto-network via API
6. Triggers channel scan + maps services to channels

| | |
|---|---|
| Web UI | http://192.168.12.236:9981 |
| HTSP | 192.168.12.236:9982 |
| M3U | http://192.168.12.236:9981/playlist/channels.m3u |
| XMLTV | http://192.168.12.236:9981/xmltv/channels |
| Status | Not yet deployed — run deploy script |

---

## Jellyfin Live TV (CT-231)

Jellyfin at http://192.168.12.231:8096 is configured with:

| Tuner | Type | URL |
|---|---|---|
| HDHomeRun CONNECT | hdhomerun | http://192.168.12.215 |

| EPG Provider | Type | URL |
|---|---|---|
| TVHeadend OTA | xmltv | http://192.168.12.172:9981/xmltv/channels |

**API key (Oz-Agent)**: `849ce95e446c4fbaa6b948c4d548b0eb`

### Re-add tuners via API (if needed)

```bash
JF_KEY=849ce95e446c4fbaa6b948c4d548b0eb
JF=http://192.168.12.231:8096

# Add HDHomeRun native tuner
curl -s -X POST "$JF/LiveTv/TunerHosts?api_key=$JF_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"Type":"hdhomerun","Url":"http://192.168.12.215","FriendlyName":"HDHomeRun CONNECT","TunerCount":2}'

# Add XMLTV EPG
curl -s -X POST "$JF/LiveTv/ListingProviders?api_key=$JF_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"Type":"xmltv","Path":"http://192.168.12.172:9981/xmltv/channels","EnableAllTuners":true}'
```

### Connect to CT-236 TVHeadend (after deploy)

```bash
JF_KEY=849ce95e446c4fbaa6b948c4d548b0eb
JF=http://192.168.12.231:8096

# Switch EPG to CT-236
curl -s -X POST "$JF/LiveTv/ListingProviders?api_key=$JF_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"Type":"xmltv","Path":"http://192.168.12.236:9981/xmltv/channels","EnableAllTuners":true}'
```

---

## TVHPlayer (Flatpak)

TVHPlayer is installed as a Flatpak on the laptop and configured to use
the local TVHeadend instance.

| | |
|---|---|
| App ID | io.github.mfat.tvhplayer |
| Config | ~/.var/app/io.github.mfat.tvhplayer/config/tvhplayer/tvhplayer.conf |
| Server | http://192.168.12.172:9981 |
| HTSP | 192.168.12.172:9982 |

```bash
# Launch
flatpak run io.github.mfat.tvhplayer

# Reconfigure
cat ~/.var/app/io.github.mfat.tvhplayer/config/tvhplayer/tvhplayer.conf
```

To add the Tiamat TVHeadend as a second server, edit the config:

```json
{
  "servers": [
    {
      "name": "Laptop TVHeadend",
      "url": "http://192.168.12.172:9981",
      "username": "",
      "password": ""
    },
    {
      "name": "Tiamat TVHeadend (CT-236)",
      "url": "http://192.168.12.236:9981",
      "username": "",
      "password": ""
    }
  ]
}
```

---

## OTA Channels (46 total — Louisville, KY)

Scan results from HDHomeRun CONNECT (1048EEE4):

| Ch | Network | Description |
|---|---|---|
| 3.1 | WAVE | NBC affiliate |
| 3.2 | Bounce | |
| 3.3 | The365 | |
| 3.4 | Grit | |
| 11.1 | WHAS-HD | ABC affiliate |
| 11.2 | Crime | |
| 11.3 | Quest | |
| 11.4 | BUSTED | |
| 11.5 | NEST | |
| 11.6 | GREAT | |
| … | … | (46 channels total) |

Full channel list: `curl -s http://localhost:9981/api/mpegts/service/grid | python3 -c "import sys,json; [print(e['svcname']) for e in json.load(sys.stdin)['entries']]"`

---

## DVR / Recording

### How scheduling works

Sonarr and Radarr are **library managers**, not DVR schedulers.
The correct pipeline is:

```
1. TVHeadend schedules + records OTA via EPG autorec rules
2. Post-process script copies recording to NFS-shared inbox
3. Sonarr/Radarr scan the inbox, rename, and add to library
```

### TVHeadend Autorecs (how to schedule recordings)

Open http://192.168.12.172:9981 → **Configuration → DVR → Autorecs → Add**

| Field | Example |
|---|---|
| Title (regex) | `.*Jeopardy.*` |
| Channel | WAVE (3.1) or Any |
| Day(s) | Mon–Fri or Any |
| Time range | 19:00 – 20:00 or Any |
| DVR profile | Default |

Save → TVH records every matching show automatically.

### DVR Config (already configured via API)

| Setting | Value |
|---|---|
| Recording path | `/var/snap/tvheadend/common/recordings` |
| Retention | 7 days (auto-removed after import) |
| Post-processor | `tvh-to-arr.sh` (calls Sonarr/Radarr after each recording) |

### Post-process → Sonarr/Radarr Pipeline

Script: `/var/snap/tvheadend/common/scripts/tvh-to-arr.sh`

After each successful recording:
1. Copies `.ts` file to `tv-inbox/` or `movies-inbox/`
2. Calls `Sonarr /api/v3/command DownloadedEpisodesScan` on the inbox path
3. Sonarr matches the episode, renames it, adds to `/data/media/tv/`

Logs: `/var/snap/tvheadend/common/scripts/tvh-to-arr.log`

### One-time setup: Mount NFS inbox on CT-214 (Sonarr)

The laptop NFS-exports the recording inbox. Run these **once on Proxmox** to wire it up:

```bash
# On Proxmox host (192.168.12.242) — adds persistent NFS mount into CT-214
pct exec 214 -- bash -c "
  apt-get install -y nfs-common 2>/dev/null
  mkdir -p /data/media/tv-ota-inbox
  echo '192.168.12.172:/var/snap/tvheadend/common/recordings/tv-inbox  /data/media/tv-ota-inbox  nfs  defaults,_netdev  0  0' >> /etc/fstab
  mount -a
  echo 'NFS mounted:' \$(df -h /data/media/tv-ota-inbox | tail -1)
"

# Also add OTA inbox as Sonarr root folder (once path exists)
curl -s -X POST 'http://192.168.12.214:8989/api/v3/rootfolder' \
  -H 'X-Api-Key: 9e2127824e7446f6a2ddc5da67cfe693' \
  -H 'Content-Type: application/json' \
  -d '{"path":"/data/media/tv-ota-inbox"}'
```

### Test a recording

```bash
# Schedule a one-off recording via TVH API
SVC_UUID=$(curl -s 'http://localhost:9981/api/mpegts/service/grid' | \
  python3 -c "import sys,json; svcs=json.load(sys.stdin)['entries']; \
  print(next(s['uuid'] for s in svcs if 'WAVE' in s.get('svcname','')))")  # WAVE = NBC

# Record immediately for 5 minutes (300 seconds)
NOW=$(date +%s)
curl -s -X POST 'http://localhost:9981/api/dvr/entry/create' \
  -d "conf={\"channel\":\"$(curl -s 'http://localhost:9981/api/channel/grid' | \
    python3 -c 'import sys,json; chs=json.load(sys.stdin)[\"entries\"]; print(next(c[\"uuid\"] for c in chs if \"WAVE\" in c[\"name\"]))')\",\
  \"start\":$NOW,\"stop\":$((NOW+300)),\"title\":{\"eng\":\"OTA Test Recording\"}}"
```

### Sonarr: Add a TV show for OTA monitoring

In Sonarr (http://192.168.12.214:8989):
1. **Series → Add New** → search for a show airing OTA (e.g. "Jeopardy")
2. **Root folder**: `/data/media/tv` or `/data/media/tv-ota-inbox`
3. **Monitor**: All episodes
4. Save — Sonarr will pick up recordings from TVH automatically

---

## Troubleshooting

### TVHeadend (snap) won't start
```bash
snap logs tvheadend -n 50
systemctl status snap.tvheadend.tvheadend.service
```

### HDHomeRun not discovered
```bash
# Check device is on network
hdhomerun_config discover
curl http://192.168.12.215/discover.json

# Check TVHeadend inputs
curl -s http://localhost:9981/api/hardware/tree?uuid=root | python3 -m json.tool
```

### Channels missing after rescan
See "Re-map channels after rescan" section above.

### Jellyfin Live TV not working
```bash
# Verify HDHomeRun is reachable from CT-231
curl http://192.168.12.215/discover.json
curl http://192.168.12.215:5004/lineup.json

# Check Jellyfin log on CT-231
# /var/log/jellyfin/jellyfin*.log  (SSH in as root)
```
