#!/usr/bin/env bash
# =============================================================================
# verify-pipeline.sh — End-to-end media pipeline diagnostic
#
# Validates every link in the chain:
#   Jellyseerr → Sonarr/Radarr → Prowlarr → qBittorrent (VPN) → Jellyfin
#
# Run from any machine with LAN access to the Tiamat stack.
# Set API keys via env vars or they default to the Tiamat production keys.
# =============================================================================

set -o pipefail

# ── Service endpoints ────────────────────────────────────────────────────────
JELLYSEERR_URL="${JELLYSEERR_URL:-http://192.168.12.151:5055}"
SONARR_URL="${SONARR_URL:-http://192.168.12.214:8989}"
RADARR_URL="${RADARR_URL:-http://192.168.12.225:7878}"
PROWLARR_URL="${PROWLARR_URL:-http://192.168.12.210:9696}"
JACKETT_URL="${JACKETT_URL:-http://192.168.12.211:9117}"
QBIT_URL="${QBIT_URL:-http://192.168.12.212:8080}"
RDTCLIENT_URL="${RDTCLIENT_URL:-http://192.168.12.213:6500}"
VPN_PROXY="${VPN_PROXY:-http://192.168.12.101:8888}"
JELLYFIN_URL="${JELLYFIN_URL:-http://192.168.12.231:8096}"
FLARESOLVERR_URL="${FLARESOLVERR_URL:-http://192.168.12.102:8191}"
BYPARR_URL="${BYPARR_URL:-http://192.168.12.109:8191}"

# ── API keys (from monitor-media-stack.sh defaults) ──────────────────────────
SONARR_KEY="${SONARR_KEY:-9e2127824e7446f6a2ddc5da67cfe693}"
RADARR_KEY="${RADARR_KEY:-19e51404b34548aabf48076073898d0d}"
PROWLARR_KEY="${PROWLARR_KEY:-6719026a4a5042a99897597122fa4495}"
READARR_KEY="${READARR_KEY:-19566aa7fb90487ebd2c643ad8c6595d}"
JELLYSEERR_API_KEY="${JELLYSEERR_API_KEY:-}"  # Optional: if set, queries auth-gated /api/v1/settings/* endpoints

# ── Counters ─────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
WARN=0

check_pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}
check_fail() {
  echo "  ✗ $1"
  FAIL=$((FAIL + 1))
}
check_warn() {
  echo "  ⚠ $1"
  WARN=$((WARN + 1))
}

http_code() {
  local code
  for _ in 1 2 3; do
    code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 15 "$@" 2>/dev/null)
    # %{http_code} prints concatenated codes when redirects are followed; take last 3 chars
    code="${code: -3}"
    if [[ "$code" =~ ^[1-5][0-9][0-9]$ ]]; then
      printf '%s' "$code"
      return 0
    fi
  done
  printf '000'
}

# Curl helper with consistent longer timeout for API queries.
# Retries up to 3 times so transient IO contention on Tiamat (e.g. during a
# vzdump backup) doesn't false-positive a "broken" pipeline.
api_curl() {
  local out
  for _ in 1 2 3; do
    out=$(curl -s --max-time 30 "$@" 2>/dev/null)
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
  done
  return 1
}

json_val() {
  python3 -c "$1" 2>/dev/null
}

echo "============================================================"
echo "  Media Pipeline Verification — $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 1. VPN Kill-Switch Proxy (CT-101)
# ─────────────────────────────────────────────────────────────────────────────
echo "[1/8] VPN Kill-Switch Proxy (CT-101:8888)"
VPN_EXIT=$(curl -s --max-time 10 -x "$VPN_PROXY" https://icanhazip.com 2>/dev/null | tr -d '\r\n ')
if [ -n "$VPN_EXIT" ]; then
  check_pass "Proxy alive — exit IP: $VPN_EXIT"
else
  check_fail "VPN proxy unreachable — ALL downloads will stall"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 2. Cloudflare bypass — Byparr (CT-109, primary) / FlareSolverr (CT-102, backup)
#    Byparr is the primary using Camoufox/Playwright; FlareSolverr is the
#    legacy fallback. Byparr down + FlareSolverr down is a critical gap.
# ─────────────────────────────────────────────────────────────────────────────
echo "[2/8] Cloudflare bypass (Byparr primary CT-109 / FlareSolverr backup CT-102)"
BYPARR_CODE=$(http_code "$BYPARR_URL")
FLARE_CODE=$(http_code "$FLARESOLVERR_URL")
# Byparr serves 405 on GET / (only POST allowed) — that's a healthy signal
if [[ "$BYPARR_CODE" =~ ^(200|301|302|405)$ ]]; then
  check_pass "Byparr responding (HTTP $BYPARR_CODE) — PRIMARY"
  if [[ "$FLARE_CODE" =~ ^(200|301|302)$ ]]; then
    check_pass "FlareSolverr responding (HTTP $FLARE_CODE) — backup"
  else
    check_warn "FlareSolverr down (HTTP $FLARE_CODE) — backup unavailable; Byparr is sole CF bypass"
  fi
elif [[ "$FLARE_CODE" =~ ^(200|301|302)$ ]]; then
  check_warn "Byparr down (HTTP $BYPARR_CODE) — PRIMARY unavailable, falling back to FlareSolverr (HTTP $FLARE_CODE)"
else
  check_fail "No CF bypass available (Byparr=$BYPARR_CODE, FlareSolverr=$FLARE_CODE) — Cloudflare-protected indexers will fail"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 3. Prowlarr — indexers + app sync
# ─────────────────────────────────────────────────────────────────────────────
echo "[3/8] Prowlarr (CT-210:9696)"
PROWLARR_CODE=$(http_code "$PROWLARR_URL")
if [ "$PROWLARR_CODE" = "200" ] || [ "$PROWLARR_CODE" = "302" ] || [ "$PROWLARR_CODE" = "301" ]; then
  check_pass "Prowlarr responding (HTTP $PROWLARR_CODE)"
else
  check_fail "Prowlarr down (HTTP $PROWLARR_CODE) — no indexer searches possible"
fi

# Indexer count
INDEXER_COUNT=$(api_curl "$PROWLARR_URL/api/v1/indexer" -H "X-Api-Key: $PROWLARR_KEY" | \
  json_val 'import sys,json; print(len(json.load(sys.stdin)))' || echo "0")
if [ "$INDEXER_COUNT" -gt 0 ] 2>/dev/null; then
  check_pass "Prowlarr has $INDEXER_COUNT indexers"
else
  check_fail "Prowlarr has 0 indexers — searches will return nothing"
fi

# App sync
APP_SYNC=$(api_curl "$PROWLARR_URL/api/v1/applications" -H "X-Api-Key: $PROWLARR_KEY" | \
  json_val 'import sys,json; apps=json.load(sys.stdin); print(" ".join(a.get("name","?") for a in apps))' || echo "")
if [ -n "$APP_SYNC" ]; then
  check_pass "Prowlarr syncs to: $APP_SYNC"
else
  check_warn "Prowlarr has no app sync targets — indexers won't push to Sonarr/Radarr"
fi

# Jackett (CT-211) is the secondary indexer manager. Prowlarr is primary; if
# Jackett is down it's advisory only — the *arrs use Prowlarr's syncs.
JACKETT_CODE=$(http_code "$JACKETT_URL")
if [[ "$JACKETT_CODE" =~ ^(200|301|302)$ ]]; then
  check_pass "Jackett responding (HTTP $JACKETT_CODE) — secondary"
else
  check_warn "Jackett down (HTTP $JACKETT_CODE) — secondary indexer manager; Prowlarr still works"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 4. Download clients — RDT-Client (primary) + qBittorrent (secondary)
#    RDT-Client (CT-213) is the primary; qBit (CT-212) is a fallback. Only
#    RDT-Client being unhealthy is a critical failure.
# ─────────────────────────────────────────────────────────────────────────────
echo "[4/8] Download clients (RDT-Client primary CT-213 / qBit secondary CT-212)"
RDT_CODE=$(http_code "$RDTCLIENT_URL")
if [[ "$RDT_CODE" =~ ^(200|301|302|401)$ ]]; then
  check_pass "RDT-Client responding (HTTP $RDT_CODE) — PRIMARY"
else
  check_fail "RDT-Client down (HTTP $RDT_CODE) — downloads will fail"
fi
QBIT_CODE=$(http_code "$QBIT_URL")
if [[ "$QBIT_CODE" =~ ^(200|301|302|401)$ ]]; then
  check_pass "qBittorrent responding (HTTP $QBIT_CODE) — secondary"
else
  check_warn "qBittorrent down (HTTP $QBIT_CODE) — secondary client; RDT-Client still works"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 5. Sonarr — download client + Jellyfin notification
# ─────────────────────────────────────────────────────────────────────────────
echo "[5/8] Sonarr (CT-214:8989)"
SONARR_CODE=$(http_code "$SONARR_URL")
if [ "$SONARR_CODE" = "200" ] || [ "$SONARR_CODE" = "302" ] || [ "$SONARR_CODE" = "301" ]; then
  check_pass "Sonarr responding (HTTP $SONARR_CODE)"
else
  check_fail "Sonarr down (HTTP $SONARR_CODE) — TV requests will never process"
fi

# Download clients
SONARR_DL_CLIENTS=$(api_curl "$SONARR_URL/api/v3/downloadclient" -H "X-Api-Key: $SONARR_KEY" | \
  json_val 'import sys,json; clients=json.load(sys.stdin); enabled=[c for c in clients if c.get("enable")]; print(len(enabled))' || echo "0")
if [ "$SONARR_DL_CLIENTS" -gt 0 ] 2>/dev/null; then
  check_pass "Sonarr has $SONARR_DL_CLIENTS enabled download client(s)"
else
  check_fail "Sonarr has no enabled download clients — grabs will fail"
fi

# Jellyfin notification
SONARR_JF_NOTIF=$(api_curl "$SONARR_URL/api/v3/notification" -H "X-Api-Key: $SONARR_KEY" | \
  json_val 'import sys,json; notifs=json.load(sys.stdin); jf=[n for n in notifs if n.get("implementation") in ("MediaBrowser","Emby","Jellyfin")]; print(len(jf))' || echo "0")
if [ "$SONARR_JF_NOTIF" -gt 0 ] 2>/dev/null; then
  check_pass "Sonarr has Jellyfin notification configured"
else
  check_warn "Sonarr has NO Jellyfin notification — imported content won't appear until next scheduled scan"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 6. Radarr — download client + Jellyfin notification
# ─────────────────────────────────────────────────────────────────────────────
echo "[6/8] Radarr (CT-215 @ 192.168.12.225:7878)"
RADARR_CODE=$(http_code "$RADARR_URL")
if [ "$RADARR_CODE" = "200" ] || [ "$RADARR_CODE" = "302" ] || [ "$RADARR_CODE" = "301" ]; then
  check_pass "Radarr responding (HTTP $RADARR_CODE)"
else
  check_fail "Radarr down (HTTP $RADARR_CODE) — movie requests will never process"
fi

RADARR_DL_CLIENTS=$(api_curl "$RADARR_URL/api/v3/downloadclient" -H "X-Api-Key: $RADARR_KEY" | \
  json_val 'import sys,json; clients=json.load(sys.stdin); enabled=[c for c in clients if c.get("enable")]; print(len(enabled))' || echo "0")
if [ "$RADARR_DL_CLIENTS" -gt 0 ] 2>/dev/null; then
  check_pass "Radarr has $RADARR_DL_CLIENTS enabled download client(s)"
else
  check_fail "Radarr has no enabled download clients — grabs will fail"
fi

RADARR_JF_NOTIF=$(api_curl "$RADARR_URL/api/v3/notification" -H "X-Api-Key: $RADARR_KEY" | \
  json_val 'import sys,json; notifs=json.load(sys.stdin); jf=[n for n in notifs if n.get("implementation") in ("MediaBrowser","Emby","Jellyfin")]; print(len(jf))' || echo "0")
if [ "$RADARR_JF_NOTIF" -gt 0 ] 2>/dev/null; then
  check_pass "Radarr has Jellyfin notification configured"
else
  check_warn "Radarr has NO Jellyfin notification — imported content won't appear until next scheduled scan"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 7. Jellyseerr — connections to Sonarr/Radarr
# ─────────────────────────────────────────────────────────────────────────────
echo "[7/8] Jellyseerr (CT-242:5055)"
SEERR_CODE=$(http_code "$JELLYSEERR_URL")
# Jellyseerr redirects unauthenticated UI requests to /login (307); that's healthy.
if [[ "$SEERR_CODE" =~ ^(200|301|302|307|308)$ ]]; then
  check_pass "Jellyseerr responding (HTTP $SEERR_CODE)"
else
  check_fail "Jellyseerr down (HTTP $SEERR_CODE) — no new requests possible"
fi

# Check Sonarr/Radarr config in Jellyseerr.
# These endpoints require admin auth; without an API key Jellyseerr returns the
# /login redirect (which yields 0 entries) and we can't actually verify config.
if [ -n "$JELLYSEERR_API_KEY" ]; then
  SEERR_SONARR=$(api_curl -H "X-Api-Key: $JELLYSEERR_API_KEY" "$JELLYSEERR_URL/api/v1/settings/sonarr" | \
    json_val 'import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d, list) else 0)' || echo "0")
  if [ "$SEERR_SONARR" -gt 0 ] 2>/dev/null; then
    check_pass "Jellyseerr has $SEERR_SONARR Sonarr server(s)"
  else
    check_fail "Jellyseerr has no Sonarr servers — TV requests go nowhere"
  fi

  SEERR_RADARR=$(api_curl -H "X-Api-Key: $JELLYSEERR_API_KEY" "$JELLYSEERR_URL/api/v1/settings/radarr" | \
    json_val 'import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d, list) else 0)' || echo "0")
  if [ "$SEERR_RADARR" -gt 0 ] 2>/dev/null; then
    check_pass "Jellyseerr has $SEERR_RADARR Radarr server(s)"
  else
    check_fail "Jellyseerr has no Radarr servers — movie requests go nowhere"
  fi
else
  check_warn "Jellyseerr Sonarr/Radarr config not verified (set JELLYSEERR_API_KEY env var to enable)"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 8. Jellyfin — health + libraries
# ─────────────────────────────────────────────────────────────────────────────
echo "[8/8] Jellyfin (CT-231:8096)"
JF_HEALTH=$(curl -s --max-time 15 "$JELLYFIN_URL/health" 2>/dev/null)
if echo "$JF_HEALTH" | grep -qi "healthy"; then
  check_pass "Jellyfin healthy"
else
  JF_CODE=$(http_code "$JELLYFIN_URL")
  if [ "$JF_CODE" = "200" ] || [ "$JF_CODE" = "302" ]; then
    check_pass "Jellyfin responding (HTTP $JF_CODE)"
  else
    check_fail "Jellyfin down (HTTP $JF_CODE) — content won't be playable"
  fi
fi

# Public system info
JF_VERSION=$(api_curl "$JELLYFIN_URL/System/Info/Public" | \
  json_val 'import sys,json; d=json.load(sys.stdin); print(d.get("Version","?"))' || echo "?")
JF_WIZARD=$(api_curl "$JELLYFIN_URL/System/Info/Public" | \
  json_val 'import sys,json; d=json.load(sys.stdin); print(str(d.get("StartupWizardCompleted",False)).lower())' || echo "false")
if [ "$JF_WIZARD" = "true" ]; then
  check_pass "Jellyfin v$JF_VERSION — setup wizard completed"
else
  check_warn "Jellyfin v$JF_VERSION — setup wizard NOT completed"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo "============================================================"
echo "  Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "============================================================"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "  PIPELINE BROKEN — $FAIL critical failure(s) found."
  echo "  Requests from Jellyseerr may not reach Jellyfin."
  echo ""
  echo "  Run the self-healing watchdog to auto-fix what it can:"
  echo "    python3 scripts/media-pipeline-watchdog.py /etc/media-pipeline-watchdog.json"
  echo ""
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo ""
  echo "  Pipeline functional but $WARN issue(s) may cause delays."
  echo ""
  exit 0
else
  echo ""
  echo "  Pipeline is BULLETPROOF. Seerr → Jellyfin fully connected."
  echo ""
  exit 0
fi
