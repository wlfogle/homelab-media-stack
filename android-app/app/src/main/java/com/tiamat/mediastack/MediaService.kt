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
 * Static service list — all IPs/ports for the Tiamat media stack.
 * baseUrl = http://192.168.12.110 (CT-110 media container)
 * AdGuard runs on CT-102 = 192.168.12.102
 */
object ServiceRepository {

    fun getServices(baseUrl: String): List<MediaService> = listOf(

        // ── Dashboard / Home ──────────────────────────────────────────────────
        MediaService(
            name        = "Homarr",
            url         = "$baseUrl:7575",
            description = "Home dashboard — links to all services",
            iconResId   = R.drawable.ic_service_homarr,
            category    = MediaService.Category.DASHBOARD
        ),

        // ── Media Servers ─────────────────────────────────────────────────────
        MediaService(
            name        = "Jellyfin",
            url         = "$baseUrl:8096",
            description = "Open-source media server — TV, movies, music",
            iconResId   = R.drawable.ic_service_jellyfin,
            category    = MediaService.Category.MEDIA
        ),
        MediaService(
            name        = "Plex",
            url         = "$baseUrl:32400/web",
            description = "Plex Media Server — Live TV via HDHomeRun + PlayOn recordings",
            iconResId   = R.drawable.ic_service_plex,
            category    = MediaService.Category.MEDIA
        ),

        // ── Requests ──────────────────────────────────────────────────────────
        MediaService(
            name        = "Overseerr",
            url         = "$baseUrl:5055",
            description = "Request movies & TV for Plex and Jellyfin",
            iconResId   = R.drawable.ic_service_overseerr,
            category    = MediaService.Category.REQUEST
        ),

        // ── The Arr Suite ──────────────────────────────────────────────────────
        MediaService(
            name        = "Sonarr",
            url         = "$baseUrl:8989",
            description = "TV series automation",
            iconResId   = R.drawable.ic_service_sonarr,
            category    = MediaService.Category.ARR
        ),
        MediaService(
            name        = "Radarr",
            url         = "$baseUrl:7878",
            description = "Movie automation",
            iconResId   = R.drawable.ic_service_radarr,
            category    = MediaService.Category.ARR
        ),
        MediaService(
            name        = "Prowlarr",
            url         = "$baseUrl:9696",
            description = "Indexer manager for Sonarr & Radarr",
            iconResId   = R.drawable.ic_service_prowlarr,
            category    = MediaService.Category.ARR
        ),
        MediaService(
            name        = "Bazarr",
            url         = "$baseUrl:6767",
            description = "Subtitle manager",
            iconResId   = R.drawable.ic_service_bazarr,
            category    = MediaService.Category.ARR
        ),

        // ── Downloads ─────────────────────────────────────────────────────────
        MediaService(
            name        = "qBittorrent",
            url         = "$baseUrl:9090",
            description = "Torrent client — proxied through WireGuard VPN",
            iconResId   = R.drawable.ic_service_qbit,
            category    = MediaService.Category.DOWNLOAD
        ),

        // ── Analytics ─────────────────────────────────────────────────────────
        MediaService(
            name        = "Tautulli",
            url         = "$baseUrl:8181",
            description = "Plex analytics and monitoring",
            iconResId   = R.drawable.ic_service_tautulli,
            category    = MediaService.Category.ANALYTICS
        ),

        // ── Network ───────────────────────────────────────────────────────────
        MediaService(
            name        = "AdGuard Home",
            url         = "http://192.168.12.102:3000",
            description = "Network-wide ad blocking and DNS",
            iconResId   = R.drawable.ic_service_adguard,
            category    = MediaService.Category.NETWORK
        )
    )
}
