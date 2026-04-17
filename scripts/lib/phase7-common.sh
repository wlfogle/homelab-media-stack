# shellcheck shell=bash
# ============================================================
# Phase 7 shared helpers — sourced by deploy-*.sh scripts
# Must be sourced, not executed. Runs on the Proxmox host (Tiamat).
# ============================================================

# Guard against double-source
if [ -n "${__PHASE7_COMMON_LOADED:-}" ]; then return 0; fi
__PHASE7_COMMON_LOADED=1

set -Eeuo pipefail

# ── Defaults (override via env) ──────────────────────────────
TEMPLATE="${TEMPLATE:-local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"
GATEWAY="${GATEWAY:-192.168.12.1}"
SUBNET_CIDR="${SUBNET_CIDR:-24}"
DNS="${DNS:-8.8.8.8 1.1.1.1}" # Match existing CTs (AdGuard on Bahamut is for physical LAN clients only; not reachable from LXC namespace)
TZ="${TZ:-America/New_York}"

# ── Logging ──────────────────────────────────────────────────
p7_info()  { printf '\033[1;36m[INFO]\033[0m  %s\n' "$*"; }
p7_ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
p7_warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
p7_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
p7_step()  { printf '\n\033[1;35m── %s ──\033[0m\n' "$*"; }

# ── Proxmox preflight ────────────────────────────────────────
p7_require_pve() {
  command -v pct >/dev/null 2>&1 || { p7_error "pct not found — run on the Proxmox host."; exit 10; }
  [ "$(id -u)" -eq 0 ] || { p7_error "Must run as root."; exit 11; }
  pveam list local 2>/dev/null | grep -q 'debian-12-standard_12.12' || {
    p7_warn "Debian 12 template missing on local; attempting pveam update + download"
    pveam update >/dev/null 2>&1 || true
    pveam download local debian-12-standard_12.12-1_amd64.tar.zst >/dev/null 2>&1 || {
      p7_error "Failed to fetch debian-12 template."; exit 12; }
  }
}

# ── CT lifecycle ─────────────────────────────────────────────
p7_ct_exists() { pct status "$1" >/dev/null 2>&1; }

p7_ct_destroy_if_exists() {
  local ctid="$1"
  if p7_ct_exists "$ctid"; then
    p7_info "Destroying existing CT-${ctid}..."
    pct stop  "$ctid" >/dev/null 2>&1 || true
    sleep 1
    pct destroy "$ctid" --purge 1 --destroy-unreferenced-disks 1 >/dev/null 2>&1 || {
      p7_error "pct destroy ${ctid} failed"; return 1; }
    p7_ok "CT-${ctid} destroyed."
  fi
}

# Args: ctid hostname ip cpu ram disk_gb [extra_pct_args...]
p7_ct_create() {
  local ctid="$1" hostname="$2" ip="$3" cpu="$4" ram="$5" disk="$6"
  shift 6
  if p7_ct_exists "$ctid"; then
    p7_info "CT-${ctid} (${hostname}) already exists — skipping create."
    return 0
  fi
  p7_info "Creating CT-${ctid} ${hostname} @ ${ip}/${SUBNET_CIDR} (${cpu}c/${ram}M/${disk}G)"
  pct create "$ctid" "$TEMPLATE" \
    --hostname "$hostname" \
    --cores "$cpu" --memory "$ram" --swap "$((ram/2))" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${ip}/${SUBNET_CIDR},gw=${GATEWAY},type=veth" \
    --nameserver "$DNS" \
    --storage "$STORAGE" --rootfs "${STORAGE}:${disk}" \
    --unprivileged 1 --features "nesting=1" \
    --onboot 1 \
    "$@" >/dev/null
  p7_ok "CT-${ctid} created."
}

p7_ct_start_and_wait() {
  local ctid="$1" tries=0
  if [ "$(pct status "$ctid" 2>/dev/null | awk '{print $2}')" != "running" ]; then
    pct start "$ctid" >/dev/null 2>&1 || true
    # give systemd / veth time to attach to the bridge
    sleep 8
  fi
  until pct exec "$ctid" -- true >/dev/null 2>&1; do
    tries=$((tries+1))
    [ $tries -gt 60 ] && { p7_error "CT-${ctid} failed to come up"; return 1; }
    sleep 1
  done
  # wait for network — veth attach + link up can take 30–60 s on first boot
  tries=0
  until pct exec "$ctid" -- getent hosts deb.debian.org >/dev/null 2>&1; do
    tries=$((tries+1))
    [ $tries -gt 120 ] && { p7_error "CT-${ctid} DNS not resolving after 120 s"; return 1; }
    sleep 2
  done
  p7_ok "CT-${ctid} is up."
}

# Run bash script inside CT with strict mode. Usage: p7_ct_run CTID <<'EOF' ... EOF
p7_ct_run() {
  local ctid="$1"
  pct exec "$ctid" -- bash -c 'set -Eeuo pipefail; export DEBIAN_FRONTEND=noninteractive; export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; '"$(cat)"
}

# ── *arr and Jellyfin API-key discovery (runs on Tiamat) ─────
# These helpers read secrets from existing CT state; never echo them to
# anywhere outside the intended config file.

p7_arr_key() {
  # $1 = ctid, $2 = app name (sonarr/radarr/readarr/lidarr/prowlarr)
  local ctid="$1" app="$2"
  pct exec "$ctid" -- bash -c \
    "grep -oPm1 '(?<=<ApiKey>)[^<]+' /var/lib/${app}/config.xml 2>/dev/null" 2>/dev/null | tr -d '\r\n'
}

p7_jellyfin_key_get_or_create() {
  # Returns a Jellyfin API key dedicated to Jellystat. Creates one if missing.
  # $1 = jellyfin ctid (default 231)
  local ctid="${1:-231}"
  local existing
  existing=$(pct exec "$ctid" -- bash -c \
    "sqlite3 /var/lib/jellyfin/data/jellyfin.db \"SELECT AccessToken FROM ApiKeys WHERE Name='Jellystat' LIMIT 1\"" 2>/dev/null | tr -d '\r\n')
  if [ -n "$existing" ]; then echo "$existing"; return 0; fi

  # Need a bootstrap admin key (from any existing entry). Prefer a Jellyseerr key.
  local admin
  admin=$(pct exec "$ctid" -- bash -c \
    "sqlite3 /var/lib/jellyfin/data/jellyfin.db \"SELECT AccessToken FROM ApiKeys LIMIT 1\"" 2>/dev/null | tr -d '\r\n')
  if [ -z "$admin" ]; then
    p7_error "Jellyfin has no existing API keys to bootstrap from. Create one via Dashboard → API Keys, then re-run."
    return 1
  fi

  local jfip
  jfip=$(pct exec "$ctid" -- hostname -I 2>/dev/null | awk '{print $1}')
  [ -z "$jfip" ] && jfip="192.168.12.231"

  # POST /Auth/Keys?App=Jellystat — creates a new key; then list to fetch value
  pct exec "$ctid" -- bash -c \
    "curl -fsS -X POST -H 'X-Emby-Token: ${admin}' 'http://127.0.0.1:8096/Auth/Keys?App=Jellystat' >/dev/null" 2>/dev/null || true

  existing=$(pct exec "$ctid" -- bash -c \
    "sqlite3 /var/lib/jellyfin/data/jellyfin.db \"SELECT AccessToken FROM ApiKeys WHERE Name='Jellystat' ORDER BY DateCreated DESC LIMIT 1\"" 2>/dev/null | tr -d '\r\n')
  if [ -z "$existing" ]; then
    p7_error "Failed to mint Jellystat API key in Jellyfin."
    return 1
  fi
  echo "$existing"
}

# ── Convenience: atomic write inside CT ──────────────────────
p7_ct_write() {
  # $1 ctid, $2 path-inside-ct; stdin=content; optional $3 mode, $4 owner
  local ctid="$1" dst="$2" mode="${3:-0644}" owner="${4:-root:root}"
  local tmp
  tmp=$(mktemp)
  cat > "$tmp"
  pct push "$ctid" "$tmp" "$dst" --perms "$mode" --user "${owner%%:*}" --group "${owner##*:}" >/dev/null
  rm -f "$tmp"
}

# ── HTTP health check ────────────────────────────────────────
p7_http_ok() {
  local url="$1" expect="${2:-200}" tries="${3:-30}"
  local code
  for _ in $(seq 1 "$tries"); do
    code=$(curl -fsS --max-time 3 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)
    if [[ "$code" =~ ^(200|302|301|401|403)$ ]]; then
      printf '%s' "$code"
      return 0
    fi
    sleep 2
  done
  printf '%s' "${code:-000}"
  return 1
}
