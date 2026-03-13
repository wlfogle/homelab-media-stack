# TiamatsStack Android App

WebView-based controller/monitor for the Tiamat homelab media stack.
Works on phones, tablets, and all Fire TV devices (via LEANBACK_LAUNCHER).

## Services covered

| Service      | URL                         | Purpose                      |
|-------------|------------------------------|------------------------------|
| Homarr       | 192.168.12.110:7575         | Home dashboard               |
| Jellyfin     | 192.168.12.110:8096         | Open-source media server     |
| Plex         | 192.168.12.110:32400/web    | Plex + HDHomeRun Live TV     |
| Overseerr    | 192.168.12.110:5055         | Request movies & TV          |
| Sonarr       | 192.168.12.110:8989         | TV automation                |
| Radarr       | 192.168.12.110:7878         | Movie automation             |
| Prowlarr     | 192.168.12.110:9696         | Indexer manager              |
| Bazarr       | 192.168.12.110:6767         | Subtitles                    |
| qBittorrent  | 192.168.12.110:9090         | Torrents (VPN protected)     |
| Tautulli     | 192.168.12.110:8181         | Plex analytics               |
| AdGuard Home | 192.168.12.102:3000         | DNS / ad blocking            |

## Build

```bash
# Prerequisites
sudo nala install openjdk-17-jdk android-tools-adb

# Set Android SDK path
export ANDROID_HOME=~/Android/Sdk   # or wherever your SDK lives

# Build debug APKs (mobile + Fire TV flavors)
chmod +x build-app.sh
./build-app.sh

# Build AND sideload to all 3 Fire TVs (192.168.12.51-53)
./build-app.sh install-firetv

# Install to connected phone/tablet
./build-app.sh install-mobile
```

## Product flavors

| Flavor  | Package suffix | Launcher category      | Notes                    |
|---------|----------------|------------------------|--------------------------|
| mobile  | .mobile        | LAUNCHER               | Portrait phone/tablet UI |
| firetv  | .firetv        | LEANBACK_LAUNCHER      | 4-col TV grid, D-pad nav |

## Fire TV sideload setup

1. On each Fire TV: **Settings → My Fire TV → Developer Options → ADB Debugging: ON**
2. Enable **Apps from Unknown Sources** on the same screen
3. Run `./build-app.sh install-firetv`

The app shows up in the Fire TV **Your Apps & Channels** row under TiamatsStack.

## Changing the server IP

Edit `app/src/main/res/values/strings.xml`:
```xml
<string name="server_base_url">http://YOUR_SERVER_IP</string>
```
Then rebuild.

## Project structure

```
android-app/
├── app/
│   └── src/main/
│       ├── java/com/tiamat/mediastack/
│       │   ├── MainActivity.kt       # Phone/tablet launcher
│       │   ├── TvMainActivity.kt     # Fire TV / Android TV launcher
│       │   ├── WebViewActivity.kt    # WebView with D-pad support
│       │   ├── MediaService.kt       # Data model + ServiceRepository
│       │   └── ServiceAdapter.kt    # RecyclerView adapter
│       ├── res/
│       │   ├── layout/               # XML layouts
│       │   ├── values/               # strings, colors, themes
│       │   ├── drawable/             # vector icons
│       │   └── xml/                  # network_security_config.xml
│       └── AndroidManifest.xml
├── build-app.sh                      # Build & sideload script
└── README.md
```
