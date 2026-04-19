# Home Assistant — VM-500

**Status**: Online  
**URL**: `http://192.168.12.250:8123` · `http://ha.tiamat.local`  
**Type**: HAOS (Home Assistant OS) — bare VM, not LXC  
**Traefik route**: `ha.tiamat.local` → `192.168.12.250:8123`  
**Phase**: Phase 10 (added 2026-04-07)

---

## Config files

Source-of-truth configs live in `infrastructure/homeassistant/`. Deploy with:

```bash
bash infrastructure/homeassistant/deploy.sh --dry-run   # preview
bash infrastructure/homeassistant/deploy.sh             # apply + restart
```

| File | Purpose |
|------|---------|
| `configuration.yaml` | Main config — HTTP, integrations, file includes |
| `binary_sensor.yaml` | Ping-based health monitors for all 20 stack services |
| `sensors.yaml` | command_line + REST sensors (Jellyfin streams, queue sizes, Ollama) |
| `rest_commands.yaml` | GET-method REST commands to every service |
| `scripts.yaml` | Voice-triggered scripts (movie_night, system_status, etc.) |
| `automations.yaml` | Service-down alerts, daily 08:00 briefing, weekly library scan |
| `intent_script.yaml` | HA Assist "Computer, …" intents backed by Ollama |
| `secrets.yaml.example` | API key template — copy to `secrets.yaml` and fill in |

---

## Issues fixed (from awesome-stack docs)

| # | Issue | Fix |
|---|-------|-----|
| 1 | Template sensor invalid device classes | binary_sensor.yaml uses `device_class: connectivity` |
| 2 | systemmonitor platform deprecated | Replaced with `command_line` sensors |
| 3 | REST command `HEAD` not supported | All REST commands use `method: GET` |
| 4 | persistent_notification module path | Fixed in configuration.yaml |
| 5 | Plex YAML config deprecated | Removed — add Plex via UI only |
| 6 | SQLite shutdown issues | `recorder.commit_interval: 10`, `purge_keep_days: 30` |
| 7 | Network connectivity to media stack | All services defined in binary_sensor.yaml |
| 8 | HTTP `server_host` Supervisor incompatibility | Removed; using `use_x_forwarded_for` + `trusted_proxies` |

---

## Current known issues (2026-04-15 log)

| # | Issue | Severity | Action |
|---|-------|----------|--------|
| 1 | Jellyfin DLNA/HDHomeRun `media-source://` 404 | High | Disable DLNA in Jellyfin **or** disable HA media browser for Jellyfin |
| 2 | Opera 129 frontend TypeError | Low | Use Firefox/Chromium for HA UI |
| 3 | IPP printer timeout | Medium | Remove integration if printer retired |
| 4 | Login attempt from 192.168.12.242 (invalid token) | Medium | Identify caller — likely old Homarr or health-check script |
| 5 | HACS warning | Cosmetic | Ignore |
| 6 | Python 3.14 `rich` SyntaxWarning | Cosmetic | Fixed in next HA core update |

---

## Installed add-ons

- **SSH & Web Terminal** — port 22222 (used by deploy.sh)
- **HACS** — custom integrations
- **Studio Code Server** (optional — edit config in browser)

---

## Integrations (UI-configured — not YAML)

- **Jellyfin** — `192.168.12.231:8096`
- **Plex** — `192.168.12.230:32400` (token from plex.tv)
- **Ollama** — `192.168.12.172:11434` (set as conversation agent in Voice Assistants)
- **Uptime Kuma** — optional via HACS integration

---

## Ollama AI voice assistant setup

1. Settings → Voice Assistants → **Add Assistant**
2. Name: `Tiamat Computer`
3. Conversation agent: **Ollama**
4. Endpoint: `http://192.168.12.172:11434`
5. Model: `llama3.1:8b` (or `mistral:7b`)
6. Wake word: `Computer`

See `docs/VOICE-CONTROL.md` for full voice command reference.

---

## Secrets setup

```bash
cp infrastructure/homeassistant/secrets.yaml.example \
   infrastructure/homeassistant/secrets.yaml
# edit secrets.yaml with API keys from each service
```

Get API keys from:
- Sonarr: `http://192.168.12.214:8989/settings/general`
- Radarr: `http://192.168.12.225:7878/settings/general`
- Prowlarr: `http://192.168.12.210:9696/settings/general`
- Jellyfin: Settings → API Keys → + New

---

## Proxmox VM config

```
VM ID:  500
Type:   HAOS (KVM)
CPU:    2 cores (host)
RAM:    2 GB
Disk:   32 GB
IP:     192.168.12.250 (static)
Boot:   tier 1 (starts first, before all CTs)
```
