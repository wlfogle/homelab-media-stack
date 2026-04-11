package com.tiamat.mediastack

/**
 * Represents a content service shown in the dashboard.
 * The app is a search-and-add interface — the arr stack + qBittorrent
 * handle downloading, and Jellyfin/Plex auto-import finished media.
 */
data class MediaService(
    val name:        String,
    val url:         String,
    val description: String,
    val iconResId:   Int,
    val category:    String = "",
    val available:   Boolean = true
)

/**
 * Service list — per-service LXC architecture on Tiamat (192.168.12.242).
 *
 * IPs verified against live Proxmox state on 2026-04-11.
 * Static IPs: 100-107, 210-224, 230-231.
 * DHCP IPs: check with `pct exec <CT> -- hostname -I` if they change.
 */
object ServiceRepository {

    fun getServices(): List<MediaService> = listOf(

        // ── Media Players ──

        MediaService(
            name        = "Jellyfin",
            url         = "http://192.168.12.231:8096",
            description = "Watch movies, TV, music",
            iconResId   = R.drawable.ic_service_jellyfin,
            category    = "Watch"
        ),

        MediaService(
            name        = "Plex",
            url         = "http://192.168.12.230:32400/web",
            description = "Watch movies, TV, music",
            iconResId   = R.drawable.ic_service_plex,
            category    = "Watch"
        ),

        MediaService(
            name        = "Live TV",
            url         = "http://192.168.12.231:8096/web/#/livetv.html",
            description = "IPTV via Jellyfin",
            iconResId   = R.drawable.ic_service_livetv,
            category    = "Watch"
        ),

        // ── Search & Request ──

        MediaService(
            name        = "Movies & TV",
            url         = "http://192.168.12.151:5055",
            description = "Search & request via Jellyseerr",
            iconResId   = R.drawable.ic_service_overseerr,
            category    = "Search"
        ),

        MediaService(
            name        = "TV Shows",
            url         = "http://192.168.12.214:8989",
            description = "Manage via Sonarr",
            iconResId   = R.drawable.ic_service_sonarr,
            category    = "Search"
        ),

        MediaService(
            name        = "Movies",
            url         = "http://192.168.12.225:7878",
            description = "Manage via Radarr",
            iconResId   = R.drawable.ic_service_radarr,
            category    = "Search"
        ),

        MediaService(
            name        = "Books",
            url         = "http://192.168.12.217:8787",
            description = "Search & add via Readarr",
            iconResId   = R.drawable.ic_service_readarr,
            category    = "Search"
        ),

        MediaService(
            name        = "Music",
            url         = "http://192.168.12.218:8686",
            description = "Search & add via Lidarr",
            iconResId   = R.drawable.ic_service_lidarr,
            category    = "Search"
        ),

        // ── Libraries ──

        MediaService(
            name        = "Audiobooks",
            url         = "http://192.168.12.232:13378",
            description = "Browse & listen via Audiobookshelf",
            iconResId   = R.drawable.ic_service_audiobookshelf,
            category    = "Library"
        ),

        MediaService(
            name        = "eBooks",
            url         = "http://192.168.12.233:8083",
            description = "Browse & read via Calibre-Web",
            iconResId   = R.drawable.ic_service_calibreweb,
            category    = "Library"
        ),

        // ── Downloads ──

        MediaService(
            name        = "Torrents",
            url         = "http://192.168.12.212:8080",
            description = "qBittorrent — add magnets/torrents",
            iconResId   = R.drawable.ic_service_qbit,
            category    = "Downloads"
        ),

        MediaService(
            name        = "Real-Debrid",
            url         = "http://192.168.12.213:6500",
            description = "rdt-client — debrid downloads",
            iconResId   = R.drawable.ic_service_realdebrid,
            category    = "Downloads"
        ),

        MediaService(
            name        = "Indexers",
            url         = "http://192.168.12.210:9696",
            description = "Prowlarr — manage indexers",
            iconResId   = R.drawable.ic_service_prowlarr,
            category    = "Downloads"
        ),

        // ── Tools ──

        MediaService(
            name        = "Subtitles",
            url         = "http://192.168.12.188:6767",
            description = "Bazarr — subtitle management",
            iconResId   = R.drawable.ic_service_bazarr,
            category    = "Tools",
            available   = false  // CT-240 stopped
        ),

        MediaService(
            name        = "Stats",
            url         = "http://192.168.12.169:8181",
            description = "Tautulli — Plex analytics",
            iconResId   = R.drawable.ic_service_tautulli,
            category    = "Tools"
        ),

        MediaService(
            name        = "Dashboard",
            url         = "http://192.168.12.241:7575",
            description = "Homarr — service dashboard",
            iconResId   = R.drawable.ic_service_homarr,
            category    = "Tools"
        ),

        MediaService(
            name        = "AI Chat",
            url         = "http://192.168.12.221:3000",
            description = "Open WebUI — Ollama LLMs",
            iconResId   = R.drawable.ic_service_openwebui,
            category    = "Tools"
        ),

        // ── Infrastructure ──

        MediaService(
            name        = "AdGuard",
            url         = "http://192.168.12.244:3000",
            description = "DNS & ad-blocking",
            iconResId   = R.drawable.ic_service_adguard,
            category    = "Infra"
        ),

        MediaService(
            name        = "VPN",
            url         = "http://192.168.12.244:51821",
            description = "wg-easy — WireGuard clients",
            iconResId   = R.drawable.ic_service_wgeasy,
            category    = "Infra"
        ),

        MediaService(
            name        = "Passwords",
            url         = "https://192.168.12.104",
            description = "Vaultwarden",
            iconResId   = R.drawable.ic_service_vaultwarden,
            category    = "Infra"
        ),

        MediaService(
            name        = "Traefik",
            url         = "http://192.168.12.103:8080",
            description = "Reverse proxy dashboard",
            iconResId   = R.drawable.ic_service_traefik,
            category    = "Infra"
        ),

        MediaService(
            name        = "Auth",
            url         = "http://192.168.12.107:9000",
            description = "Authentik SSO",
            iconResId   = R.drawable.ic_service_authentik,
            category    = "Infra"
        )
    )
}
