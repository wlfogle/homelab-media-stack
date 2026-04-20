# Stack Status — 2026-04-20

## Live / Running
- Jellyfin CT-231 (192.168.12.231:8096) — Live TV: HDHomeRun native + XMLTV EPG
- Sonarr CT-214 (192.168.12.214:8989)
- Lidarr CT-218 (192.168.12.218:8686)
- RDT-Client CT-213 (192.168.12.213:6500)
- FlareSolverr CT-102 (192.168.12.102:8191)
- Prowlarr CT-210 (192.168.12.210:9696)
- qBittorrent CT-212 (192.168.12.212:8080)
- Jellystat, Uptime Kuma, Threadfin, Dispatcharr (Phase 7)
- TVHeadend snap (laptop, 192.168.12.172:9981) — 46 OTA channels, DVR configured
- HDHomeRun CONNECT (192.168.12.215) — firmware 20260313
- TVHPlayer flatpak (laptop)
- Home Assistant (configured, voice/Alexa/Ollama)

## Pending / Needs Action
- CT-236 TVHeadend on Tiamat: run `bash scripts/deploy-tvheadend.sh` on Proxmox
- CT-214 Sonarr NFS inbox: `pct exec 214` mount step (see docs/TVHEADEND.md)
- CT-275 Homarr: stopped — start on Proxmox, then add Live TV services via UI
- Radarr CT-215: stopped — start on Proxmox
- SSH public key for TVH post-process: authorize on CT-214
  Key: /var/snap/tvheadend/common/.ssh/tvh_id_ed25519.pub

## Traefik Live TV routes
Copy infrastructure/traefik/dynamic/live-tv.yml to Traefik CT-103 config dir.
Routes: tvheadend.tiamat.local, tvh.laptop.local, hdhomerun.tiamat.local

## Credentials
See docs/CREDENTIALS.md for all IPs, ports, API keys.
