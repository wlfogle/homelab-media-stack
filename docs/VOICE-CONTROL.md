# Voice Control — "Star Trek Computer" Mode

Control your entire Tiamat homelab with voice commands via Alexa and Home Assistant Assist backed by local Ollama AI. No cloud subscription required.

---

## Architecture

```
You speak
    │
    ▼
Alexa Echo device  ──────────────────────────────────────────┐
    │                                                         │
    │ UPnP/SSDP discovery (LAN)                              │ Smart Home skill
    ▼                                                         │ (optional cloud path)
CT-501 HABridge (192.168.12.251)                             │
Java app emulating Philips Hue bridge                        │
    │                                                         │
    │ HTTP to HA REST API                                     │
    └─────────────────────┐                                   │
                          ▼                                   │
            VM-500 Home Assistant (192.168.12.250:8123) ◄─────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
    Jellyfin CT-231   Sonarr CT-214   Ollama (laptop)
    Radarr CT-225     Prowlarr CT-210  192.168.12.172:11434
    All 20+ services via REST commands
```

**Two voice paths:**
1. **Alexa → HABridge → HA** — "Alexa, turn on movie night" (no subscription)
2. **HA Assist + Ollama** — "Computer, status report" via wake word (fully local AI)

---

## CT-501 HABridge Setup

HABridge is a Java app that emulates a Philips Hue bridge, so Alexa discovers your HA scripts as fake Hue lights — no Nabu Casa needed.

### Create the LXC

```bash
# On Tiamat Proxmox (192.168.12.242)
pct create 501 /var/lib/vz/template/cache/debian-12-standard_*.tar.zst \
  --hostname habridge \
  --memory 512 \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.12.251/24,gw=192.168.12.1 \
  --storage local-lvm \
  --rootfs local-lvm:4 \
  --unprivileged 1 \
  --start 1

pct exec 501 -- bash -c "apt-get update && apt-get install -y openjdk-17-jre-headless curl"
```

### Install HABridge

```bash
pct exec 501 -- bash -c "
  mkdir -p /opt/habridge
  cd /opt/habridge
  curl -L https://github.com/bwssytems/ha-bridge/releases/latest/download/ha-bridge.jar \
    -o ha-bridge.jar
"
```

### Configure HABridge

```bash
# Create config
pct exec 501 -- bash -c "cat > /opt/habridge/config.json <<'EOF'
{
  \"upnpConfigAddress\": \"192.168.12.251\",
  \"serverPort\": 8080,
  \"upnpPort\": 1900
}
EOF"
```

### Systemd service

```bash
pct exec 501 -- bash -c "cat > /etc/systemd/system/habridge.service <<'EOF'
[Unit]
Description=HABridge — Alexa Hue Emulation
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/habridge
ExecStart=/usr/bin/java -jar /opt/habridge/ha-bridge.jar
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now habridge"
```

### Map HA scripts to fake Hue devices

1. Open `http://192.168.12.251:8080` (HABridge web UI)
2. Click **Add Device** for each script:

| Device Name | On Command | Off Command |
|-------------|-----------|-------------|
| Movie Night | `http://192.168.12.250:8123/api/services/script/movie_night` POST | (none) |
| System Status | `http://192.168.12.250:8123/api/services/script/system_status` POST | (none) |
| AI Status | `http://192.168.12.250:8123/api/services/script/ai_status` POST | (none) |
| Download Status | `http://192.168.12.250:8123/api/services/script/download_status` POST | (none) |
| Pause All Media | `http://192.168.12.250:8123/api/services/script/pause_all_media` POST | (none) |
| Media Scan | `http://192.168.12.250:8123/api/services/script/media_scan` POST | (none) |
| Morning Routine | `http://192.168.12.250:8123/api/services/script/morning_routine` POST | (none) |
| Computer Report | `http://192.168.12.250:8123/api/services/script/computer_report` POST | (none) |

Add HA long-lived token as a header on each device:
`Authorization: Bearer YOUR_HA_LONG_LIVED_TOKEN`

Get token: HA → Profile → Long-Lived Access Tokens → Create Token

### Alexa discovery

1. Open Alexa app → Devices → **Discover Devices**
2. Wait 20–45 seconds
3. All HABridge devices appear as lights

---

## Alexa Voice Commands

Once discovered, say:

| Say | What happens |
|-----|-------------|
| "Alexa, turn on **movie night**" | Checks Jellyfin + Plex, sends status to HA |
| "Alexa, turn on **system status**" | Full Tiamat systems report |
| "Alexa, turn on **AI status**" | Checks Ollama on laptop |
| "Alexa, turn on **download status**" | Sonarr + Radarr queue summary |
| "Alexa, turn on **pause all media**" | Pauses all active Jellyfin streams |
| "Alexa, turn on **media scan**" | Triggers Jellyfin + arr library refresh |
| "Alexa, turn on **morning routine**" | Morning briefing |
| "Alexa, turn on **computer report**" | Full diagnostic across all services |

### Alexa Routines (say it naturally)

In the Alexa app, create routines:

| When you say | Action |
|-------------|--------|
| "Computer, status" | Activate "system status" |
| "Computer, movie time" | Activate "movie night" |
| "Computer, what's downloading" | Activate "download status" |
| "Computer, all systems report" | Activate "computer report" |

---

## HA Assist — Local AI with Ollama

For fully local, AI-powered voice control with natural language:

### Setup

1. **HA** → Settings → Voice Assistants → **Add Assistant**
2. Name: `Tiamat Computer`
3. Language: English
4. Conversation agent: **Ollama** (add via Settings → Integrations → Ollama first)
   - Host: `192.168.12.172`
   - Port: `11434`
   - Model: `llama3.1:8b`
5. Wake word: **"Computer"** (requires a microphone device paired to HA)

### Available intents (from intent_script.yaml)

| Say "Computer, ..." | Intent | Response |
|--------------------|--------|----------|
| "status" / "all systems" | `ComputerStatus` | Live status of all services |
| "movie night" | `ComputerMovieNight` | Jellyfin check + stream count |
| "what's downloading" | `ComputerDownloads` | Sonarr + Radarr queue |
| "AI status" | `ComputerAI` | Ollama version + endpoint |
| "pause" / "stop everything" | `ComputerPause` | Pauses all media players |
| "scan library" | `ComputerScan` | Triggers library refresh |
| "good morning" | `ComputerMorning` | Morning briefing |
| "full report" | `ComputerReport` | Complete system diagnostic |

### HA Assist via phone/tablet

Install the **Home Assistant** app → Companion app → tap the microphone icon → speak.

---

## Alexa Routines for Star Trek feel

In the Alexa app (More → Routines → +):

**"Engage"** routine:
- Trigger: "Alexa, engage"
- Actions: Activate "movie night" → Say "Tiamat entertainment systems online, Commander"

**"Red Alert"** routine:
- Trigger: "Alexa, red alert"
- Actions: Activate "system status" → Say "Running diagnostics on all Tiamat systems"

**"Stand down"** routine:
- Trigger: "Alexa, stand down"
- Actions: Activate "pause all media" → Say "All systems standing by"

---

## Monitoring

All voice-triggered actions create persistent notifications in HA visible at:
`http://192.168.12.250:8123` → Notifications (bell icon)

Service health dashboard: `http://192.168.12.248:3001` (Uptime Kuma)

---

## Troubleshooting

**Alexa can't find devices:**
```bash
# Verify HABridge is running
pct exec 501 -- systemctl status habridge
# Check HABridge web UI
curl http://192.168.12.251:8080
```

**HA script not triggering:**
```bash
# Test HA REST directly
curl -X POST http://192.168.12.250:8123/api/services/script/system_status \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json"
```

**Ollama not responding:**
```bash
curl http://192.168.12.172:11434/api/version
# If offline, check laptop is on and Ollama is running:
# ssh user@192.168.12.172 'systemctl status ollama'
```
