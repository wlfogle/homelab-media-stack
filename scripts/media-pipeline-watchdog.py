#!/usr/bin/env python3
"""Media Pipeline Watchdog — full-chain self-healing for the Seerr → Jellyfin pipeline.

Verifies and auto-repairs every link in the chain:
  Jellyseerr → Sonarr/Radarr → Prowlarr → qBittorrent (VPN) → import → Jellyfin

Designed to run on a timer (systemd or cron) from the Proxmox host or any LAN machine.
All configuration lives in a single JSON file passed as the only argument.
"""
import json
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone, timedelta
from pathlib import Path


BAD_PATTERNS = (
    ".exe",
    "executable file",
    "password protected",
    "rar password",
    "contains executable",
)

WARN_COUNT = 0
FIX_COUNT = 0


def log(msg):
    global WARN_COUNT, FIX_COUNT
    if msg.startswith("[WARN]"):
        WARN_COUNT += 1
    elif msg.startswith("[FIXED]"):
        FIX_COUNT += 1
    print(msg, flush=True)


def req(method, url, headers=None, data=None, timeout=20):
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        headers = dict(headers or {})
        headers["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=body, headers=headers or {}, method=method)
    with urllib.request.urlopen(r, timeout=timeout) as resp:
        raw = resp.read()
        ctype = resp.headers.get("Content-Type", "")
        if "application/json" in ctype and raw:
            return json.loads(raw.decode())
        return raw.decode(errors="replace")


def api_get(base, version, path, key):
    return req("GET", f"{base}/api/{version}/{path}", {"X-Api-Key": key})


def api_post(base, version, path, key, payload):
    return req("POST", f"{base}/api/{version}/{path}", {"X-Api-Key": key}, payload)


def api_delete(base, version, path, key):
    return req("DELETE", f"{base}/api/{version}/{path}", {"X-Api-Key": key})


# ---------------------------------------------------------------------------
# 1. VPN proxy health
# ---------------------------------------------------------------------------
def check_vpn_proxy(cfg):
    """Verify the VPN kill-switch proxy is alive and returning a non-LAN IP."""
    proxy_cfg = cfg.get("vpn_proxy")
    if not proxy_cfg:
        return
    proxy_url = proxy_cfg["url"]          # e.g. http://192.168.12.101:8888
    test_url = proxy_cfg.get("test_url", "https://icanhazip.com")
    home_ip = proxy_cfg.get("home_ip", "")  # optional — warn if exit matches
    try:
        proxy_handler = urllib.request.ProxyHandler({"https": proxy_url, "http": proxy_url})
        opener = urllib.request.build_opener(proxy_handler)
        with opener.open(test_url, timeout=12) as resp:
            exit_ip = resp.read().decode().strip()
        if home_ip and exit_ip == home_ip:
            log(f"[WARN] VPN proxy: exit IP {exit_ip} matches home IP — tunnel may be down")
        else:
            log(f"[OK] VPN proxy: exit IP {exit_ip}")
    except Exception as e:
        log(f"[WARN] VPN proxy ({proxy_url}): unreachable — {e}")


# ---------------------------------------------------------------------------
# 2. Jellyfin reachability
# ---------------------------------------------------------------------------
def check_jellyfin(cfg):
    """Verify Jellyfin /health returns 200."""
    jf = cfg.get("jellyfin")
    if not jf:
        return
    url = jf["url"]  # e.g. http://192.168.12.231:8096
    try:
        resp = req("GET", f"{url}/health")
        if "Healthy" in str(resp):
            log(f"[OK] Jellyfin: healthy at {url}")
        else:
            log(f"[WARN] Jellyfin: unexpected health response: {str(resp)[:120]}")
    except Exception as e:
        log(f"[WARN] Jellyfin ({url}): unreachable — {e}")


# ---------------------------------------------------------------------------
# 3. Prowlarr → app sync verification
# ---------------------------------------------------------------------------
def check_prowlarr_sync(cfg):
    """Verify Prowlarr has applications configured and synced."""
    prowlarr = cfg.get("prowlarr")
    if not prowlarr:
        return
    url = prowlarr["url"]
    key = prowlarr["api_key"]
    try:
        apps = api_get(url, "v1", "applications", key)
        if not apps:
            log(f"[WARN] Prowlarr: no applications configured — indexers won't sync to Sonarr/Radarr")
            return
        for app_entry in apps:
            name = app_entry.get("name", "?")
            sync_level = app_entry.get("syncLevel", "?")
            log(f"[OK] Prowlarr → {name}: syncLevel={sync_level}")
    except Exception as e:
        log(f"[WARN] Prowlarr ({url}): {e}")

    # Also check indexer count
    try:
        indexers = api_get(url, "v1", "indexer", key)
        count = len(indexers) if isinstance(indexers, list) else 0
        if count == 0:
            log(f"[WARN] Prowlarr: zero indexers configured")
        else:
            log(f"[OK] Prowlarr: {count} indexers configured")
    except Exception as e:
        log(f"[WARN] Prowlarr indexer check: {e}")


# ---------------------------------------------------------------------------
# 4. Jellyseerr → Sonarr/Radarr connectivity
# ---------------------------------------------------------------------------
def check_jellyseerr(cfg):
    """Verify Jellyseerr has Sonarr and Radarr servers configured."""
    seerr = cfg.get("jellyseerr")
    if not seerr:
        return
    url = seerr["url"]           # e.g. http://192.168.12.151:5055
    api_key = seerr.get("api_key", "")  # Jellyseerr API key (optional, some endpoints are public)
    headers = {}
    if api_key:
        headers["X-Api-Key"] = api_key

    # Check Sonarr services
    try:
        sonarr_settings = req("GET", f"{url}/api/v1/settings/sonarr", headers)
        if isinstance(sonarr_settings, list) and len(sonarr_settings) > 0:
            active = [s for s in sonarr_settings if s.get("isDefault") or not s.get("is4k")]
            log(f"[OK] Jellyseerr → Sonarr: {len(sonarr_settings)} server(s) configured")
        else:
            log(f"[WARN] Jellyseerr: no Sonarr servers configured — TV requests will fail")
    except Exception as e:
        log(f"[WARN] Jellyseerr Sonarr check: {e}")

    # Check Radarr services
    try:
        radarr_settings = req("GET", f"{url}/api/v1/settings/radarr", headers)
        if isinstance(radarr_settings, list) and len(radarr_settings) > 0:
            log(f"[OK] Jellyseerr → Radarr: {len(radarr_settings)} server(s) configured")
        else:
            log(f"[WARN] Jellyseerr: no Radarr servers configured — movie requests will fail")
    except Exception as e:
        log(f"[WARN] Jellyseerr Radarr check: {e}")


# ---------------------------------------------------------------------------
# 5. Sonarr/Radarr → Jellyfin notification (auto-create if missing)
# ---------------------------------------------------------------------------
def find_notification_schema(base, version, key, implementation):
    """Find the notification schema for Jellyfin/Emby."""
    schemas = api_get(base, version, "notification/schema", key)
    for schema in schemas:
        if schema.get("implementation") == implementation:
            return schema
    return None


def ensure_jellyfin_notification(app, jellyfin_cfg):
    """Ensure the arr app has a Jellyfin/Emby Connect notification so library scans
    trigger immediately on import — not hours later on the next scheduled scan."""
    if not jellyfin_cfg:
        return
    jf_url = jellyfin_cfg["url"]
    jf_api_key = jellyfin_cfg.get("api_key", "")

    notifications = api_get(app["url"], app["api_version"], "notification", app["api_key"])
    for n in notifications:
        impl = n.get("implementation", "")
        if impl in ("MediaBrowser", "Emby", "Jellyfin"):
            log(f"[OK] {app['name']}: Jellyfin notification already configured (id={n.get('id')})")
            return

    # Try to auto-create. Use MediaBrowser (Emby) implementation — works for Jellyfin too.
    for impl_name in ("MediaBrowser", "Emby"):
        schema = find_notification_schema(app["url"], app["api_version"], app["api_key"], impl_name)
        if schema:
            break
    else:
        log(f"[WARN] {app['name']}: no Jellyfin/Emby notification schema available — cannot auto-create")
        return

    payload = dict(schema)
    for k in ("id", "resource", "infoLink"):
        payload.pop(k, None)
    payload["name"] = "Jellyfin"
    payload["onDownload"] = True
    payload["onUpgrade"] = True
    payload["onImportComplete"] = True
    payload["onRename"] = True
    payload["onMovieAdded"] = False
    payload["onSeriesAdd"] = False
    payload["onHealthIssue"] = False
    payload["supportsOnDownload"] = True
    payload["supportsOnUpgrade"] = True
    payload["supportsOnImportComplete"] = True
    payload["supportsOnRename"] = True

    # Fill in fields from schema
    fields = []
    for field in payload.get("fields", []):
        f = dict(field)
        name = f.get("name", "")
        if name == "host":
            # Strip scheme and port for the host field
            parsed = urllib.parse.urlparse(jf_url)
            f["value"] = parsed.hostname
        elif name == "port":
            parsed = urllib.parse.urlparse(jf_url)
            f["value"] = parsed.port or 8096
        elif name == "apiKey":
            f["value"] = jf_api_key
        elif name == "useSsl":
            f["value"] = jf_url.startswith("https")
        elif name == "sendNotifications":
            f["value"] = True
        elif name == "updateLibrary":
            f["value"] = True
        fields.append(f)
    payload["fields"] = fields

    try:
        api_post(app["url"], app["api_version"], "notification", app["api_key"], payload)
        log(f"[FIXED] {app['name']}: Jellyfin notification created — library scans will trigger on import")
    except Exception as e:
        log(f"[WARN] {app['name']}: failed to create Jellyfin notification — {e}")


# ---------------------------------------------------------------------------
# 6. Download client health check
# ---------------------------------------------------------------------------
def check_download_client_health(app):
    """Verify at least one download client is enabled and test-passes."""
    clients = api_get(app["url"], app["api_version"], "downloadclient", app["api_key"])
    enabled = [c for c in clients if c.get("enable")]
    if not enabled:
        log(f"[WARN] {app['name']}: no enabled download clients")
        return

    any_healthy = False
    for client in enabled:
        cid = client.get("id")
        cname = client.get("name", "?")
        try:
            test_result = api_post(app["url"], app["api_version"], "downloadclient/test",
                                  app["api_key"], client)
            # Sonarr/Radarr return the client object on success, or {"isValid": false, ...} on failure
            if isinstance(test_result, dict) and test_result.get("isValid") is False:
                log(f"[WARN] {app['name']}: download client '{cname}' (id={cid}) test failed")
            else:
                log(f"[OK] {app['name']}: download client '{cname}' healthy")
                any_healthy = True
        except Exception as e:
            log(f"[WARN] {app['name']}: download client '{cname}' test error — {e}")

    if not any_healthy:
        log(f"[WARN] {app['name']}: ALL download clients are unhealthy — downloads will fail")


# ---------------------------------------------------------------------------
# Original functions (qBit client ensure + queue cleanup)
# ---------------------------------------------------------------------------
def find_qbit_schema(base, version, key):
    items = api_get(base, version, "downloadclient/schema", key)
    for item in items:
        if item.get("implementation") == "QBittorrent":
            return item
    return None


def field_value(name, media_kind, qbit):
    cat_map = qbit.get("categories", {})
    if name == "host":
        return qbit["host"]
    if name == "port":
        return qbit["port"]
    if name == "useSsl":
        return qbit.get("use_ssl", False)
    if name == "urlBase":
        return qbit.get("url_base", "")
    if name == "username":
        return qbit["username"]
    if name == "password":
        return qbit["password"]
    if name.endswith("Category") and not name.endswith("ImportedCategory"):
        return cat_map.get(media_kind, media_kind)
    if name.endswith("ImportedCategory"):
        return cat_map.get(media_kind, media_kind)
    if name in ("recentTvPriority", "olderTvPriority", "recentMoviePriority", "olderMoviePriority",
                "recentMusicPriority", "olderMusicPriority", "initialState"):
        return 0
    if name in ("sequentialOrder", "firstAndLast"):
        return False
    if name == "contentLayout":
        return "subfolder"
    return None


def ensure_qbit_client(app, qbit):
    clients = api_get(app["url"], app["api_version"], "downloadclient", app["api_key"])
    for client in clients:
        if client.get("implementation") == "QBittorrent":
            log(f"[OK] {app['name']}: qBittorrent client already configured")
            return
    schema = find_qbit_schema(app["url"], app["api_version"], app["api_key"])
    if not schema:
        log(f"[WARN] {app['name']}: no qBittorrent schema found")
        return
    payload = dict(schema)
    for k in ("id", "resource", "infoLink"):
        payload.pop(k, None)
    payload["name"] = "qBittorrent"
    payload["enable"] = True
    payload["priority"] = 1
    payload["protocol"] = "torrent"
    fields = []
    for field in payload.get("fields", []):
        f = dict(field)
        val = field_value(f.get("name"), app["media_kind"], qbit)
        if val is not None:
            f["value"] = val
        fields.append(f)
    payload["fields"] = fields
    api_post(app["url"], app["api_version"], "downloadclient", app["api_key"], payload)
    log(f"[FIXED] {app['name']}: qBittorrent client created")


def iso_to_dt(value):
    if not value:
        return None
    value = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(value)
    except Exception:
        return None


def queue_delete_path(app, item_id, remove_from_client=True, blocklist=True, skip_redownload=False):
    qs = urllib.parse.urlencode({
        "removeFromClient": str(remove_from_client).lower(),
        "blocklist": str(blocklist).lower(),
        "skipRedownload": str(skip_redownload).lower(),
    })
    return f"queue/{item_id}?{qs}"


def cleanup_queue(app, stale_hours):
    queue = api_get(app["url"], app["api_version"], "queue?page=1&pageSize=200", app["api_key"])
    now = datetime.now(timezone.utc)
    records = queue.get("records", [])
    if not records:
        log(f"[OK] {app['name']}: queue empty")
        return
    for rec in records:
        item_id = rec.get("id")
        title = rec.get("title", "?")
        joined = " ".join(
            msg
            for sm in rec.get("statusMessages", [])
            for msg in sm.get("messages", [])
        ).lower()
        added = iso_to_dt(rec.get("added"))
        age = (now - added) if added else timedelta()
        bad = any(pat in joined for pat in BAD_PATTERNS)
        stale = age > timedelta(hours=stale_hours) and rec.get("trackedDownloadStatus") in ("warning", "failed") or (
            age > timedelta(hours=stale_hours) and rec.get("trackedDownloadState") in ("importPending", "downloadFailed")
        )
        if bad:
            api_delete(app["url"], app["api_version"], queue_delete_path(app, item_id, True, True, False), app["api_key"])
            log(f"[FIXED] {app['name']}: removed poisoned release {title}")
        elif stale:
            api_delete(app["url"], app["api_version"], queue_delete_path(app, item_id, True, True, False), app["api_key"])
            log(f"[FIXED] {app['name']}: removed stale queue item {title}")


def maybe_run_hook(hook):
    try:
        if hook["method"].upper() == "POST":
            req("POST", hook["url"], hook.get("headers", {}), hook.get("body"))
        else:
            req("GET", hook["url"], hook.get("headers", {}))
        log(f"[OK] hook: {hook['name']}")
    except Exception as e:
        log(f"[WARN] hook {hook['name']}: {e}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    if len(sys.argv) != 2:
        print("usage: media-pipeline-watchdog.py /path/to/config.json", file=sys.stderr)
        sys.exit(2)
    cfg_path = Path(sys.argv[1])
    cfg = json.loads(cfg_path.read_text())
    qbit = cfg["qbittorrent"]
    stale_hours = cfg.get("stale_hours", 24)
    jellyfin_cfg = cfg.get("jellyfin")

    # ── Phase 1: Infrastructure health ──
    log("=== Phase 1: Infrastructure ===")
    check_vpn_proxy(cfg)
    check_jellyfin(cfg)
    check_prowlarr_sync(cfg)
    check_jellyseerr(cfg)

    # ── Phase 2: Per-app checks (qBit client, Jellyfin notification, download health, queue) ──
    log("=== Phase 2: App pipeline ===")
    for app in cfg.get("apps", []):
        try:
            ensure_qbit_client(app, qbit)
            check_download_client_health(app)
            ensure_jellyfin_notification(app, jellyfin_cfg)
            cleanup_queue(app, stale_hours)
        except Exception as e:
            log(f"[WARN] {app['name']}: {e}")

    # ── Phase 3: Hooks ──
    hooks = cfg.get("hooks", [])
    if hooks:
        log("=== Phase 3: Hooks ===")
        for hook in hooks:
            maybe_run_hook(hook)

    # ── Summary ──
    log(f"=== Done: {WARN_COUNT} warnings, {FIX_COUNT} auto-fixes ===")
    if WARN_COUNT > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
