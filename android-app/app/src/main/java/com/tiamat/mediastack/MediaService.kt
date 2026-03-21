package com.tiamat.mediastack

/**
 * Represents a single media-stack service shown in the dashboard.
 */
data class MediaService(
    val name:        String,
    val url:         String,
    val description: String,
    val iconResId:   Int,
    val category:    Category
) {
    enum class Category {
        MEDIA,       // Jellyfin, Plex
        REQUEST,     // Overseerr
        ARR,         // Sonarr, Radarr, Prowlarr, Bazarr
        DOWNLOAD,    // qBittorrent
        ANALYTICS,   // Tautulli
        DASHBOARD,   // Homarr
        NETWORK      // AdGuard Home
    }
}

/**
 * Static service list — per-service LXC architecture on Tiamat.
 * Each service runs in its own Proxmox CT with a dedicated IP.
 *
 * Static IPs:      Infrastructure 100-107, Download 210-224, Media 230-231
 * DHCP IPs:        Management 240+, Ziggy 900 — update if DHCP changes
 * Ziggy (Pi):      192.168.12.20  (AdGuard Home, wg-easy, Vaultwarden)
 */
object ServiceRepository {

    fun getServices(): List<MediaService> = listOf(

        // ── Media Servers ─────────────────────────────────────────────────────
        MediaService(
            name        = "Jellyfin",
            url         = "http://192.168.12.231:8096",
            description = "Open-source media server — TV, movies, music",
            iconResId   = R.drawable.ic_service_jellyfin,
            category    = MediaService.Category.MEDIA
        ),
        MediaService(
            name        = "Plex",
            url         = "http://192.168.12.230:32400/web",
            description = "Plex Media Server — Live TV via HDHomeRun + PlayOn recordings",
            iconResId   = R.drawable.ic_service_plex,
            category    = MediaService.Category.MEDIA
        ),

        // ── Requests ──────────────────────────────────────────────────────────
        MediaService(
            name        = "Jellyseerr",
            url         = "http://192.168.12.151:5055",
            description = "Request movies & TV for Jellyfin",
            iconResId   = R.drawable.ic_service_overseerr,
            category    = MediaService.Category.REQUEST
        ),

        // ── The Arr Suite ──────────────────────────────────────────────────────
        MediaService(
            name        = "Sonarr",
            url         = "http://192.168.12.214:8989",
            description = "TV series automation",
            iconResId   = R.drawable.ic_service_sonarr,
            category    = MediaService.Category.ARR
        ),
        MediaService(
            name        = "Radarr",
            url         = "http://192.168.12.215:7878",
            description = "Movie automation",
            iconResId   = R.drawable.ic_service_radarr,
            category    = MediaService.Category.ARR
        ),
        MediaService(
            name        = "Prowlarr",
            url         = "http://192.168.12.210:9696",
            description = "Indexer manager for Sonarr & Radarr",
            iconResId   = R.drawable.ic_service_prowlarr,
            category    = MediaService.Category.ARR
        ),
        MediaService(
            name        = "Bazarr",
            url         = "http://192.168.12.188:6767",
            description = "Subtitle manager",
            iconResId   = R.drawable.ic_service_bazarr,
            category    = MediaService.Category.ARR
        ),

        // ── Downloads ─────────────────────────────────────────────────────────
        MediaService(
            name        = "qBittorrent",
            url         = "http://192.168.12.212:8080",
            description = "Torrent client — proxied through WireGuard VPN",
            iconResId   = R.drawable.ic_service_qbit,
            category    = MediaService.Category.DOWNLOAD
        ),
        MediaService(
            name        = "rdt-client",
            url         = "http://192.168.12.213:6500",
            description = "Real-Debrid download client",
            iconResId   = R.drawable.ic_service_qbit,
            category    = MediaService.Category.DOWNLOAD
        ),

        // ── AI ────────────────────────────────────────────────────────────────
        MediaService(
            name        = "Open WebUI",
            url         = "http://192.168.12.223:3000",
            description = "AI chat — Ollama models via RTX 4080",
            iconResId   = R.drawable.ic_service_homarr,
            category    = MediaService.Category.DASHBOARD
        ),

        // ── Network & Infrastructure ──────────────────────────────────────────
        MediaService(
            name        = "AdGuard Home",
            url         = "http://192.168.12.20:3000",
            description = "Network-wide ad blocking and DNS",
            iconResId   = R.drawable.ic_service_adguard,
            category    = MediaService.Category.NETWORK
        ),
        MediaService(
            name        = "Authentik",
            url         = "http://192.168.12.107:9000",
            description = "SSO identity provider",
            iconResId   = R.drawable.ic_service_homarr,
            category    = MediaService.Category.NETWORK
        ),
        MediaService(
            name        = "Traefik",
            url         = "http://192.168.12.103:8080",
            description = "Reverse proxy dashboard",
            iconResId   = R.drawable.ic_service_homarr,
            category    = MediaService.Category.NETWORK
        )
    )
}
