# IPTV — Jellyfin Live TV (tvpass.org)

> Added: 2026-04-30

## Architecture

```
tvpass.org M3U  →  Jellyfin CT-231 Live TV  →  Fire TV / clients
tvpass.org EPG
```

Jellyfin's built-in M3U tuner is used directly — no Threadfin or extra proxy needed.

## Tuner Configuration

| Field | Value |
|---|---|
| Type | M3U Tuner |
| Friendly name | tvpass.org IPTV |
| M3U URL | https://tvpass.org/playlist/m3u |
| Tuner count | 4 |
| HW transcoding | Enabled (VAAPI via RX 580) |

## EPG (Electronic Program Guide)

| Field | Value |
|---|---|
| Type | XMLTV |
| URL | https://tvpass.org/epg.xml |
| Applies to | All tuners |

## Re-add via API (if needed)

```bash
JF=http://192.168.12.231:8096
KEY=849ce95e446c4fbaa6b948c4d548b0eb

# M3U Tuner
curl -s -X POST "$JF/LiveTv/TunerHosts?api_key=$KEY" \
  -H 'Content-Type: application/json' \
  -d '{"Type":"m3u","Url":"https://tvpass.org/playlist/m3u","FriendlyName":"tvpass.org IPTV","TunerCount":4,"AllowHWTranscoding":true}'

# EPG
curl -s -X POST "$JF/LiveTv/ListingProviders?api_key=$KEY" \
  -H 'Content-Type: application/json' \
  -d '{"Type":"xmltv","Path":"https://tvpass.org/epg.xml","EnableAllTuners":true}'
```

## Notes

- IPTV channels merge with existing OTA channels (HDHomeRun) in the unified TV Guide
- CT-234 (Threadfin) is installed but not configured — not needed with native M3U support
- TVHeadend plugin (CT-231) needs username configured: Dashboard → Plugins → TVHeadend
