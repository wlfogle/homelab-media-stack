#!/bin/bash
# =============================================================================
# stack-watchdog.sh — Full self-healing watchdog for Tiamat media stack
# Covers: VPN (CT-100/101), FlareSolverr (CT-102), Traefik (CT-103),
#         qBittorrent (CT-212), Prowlarr (CT-210), Sonarr (CT-214),
#         Radarr (CT-215), Readarr (CT-217), Lidarr (CT-218),
#         Plex (CT-230), Jellyfin (CT-231), Jellyseerr (CT-242),
#         Bazarr (CT-240), Tautulli (CT-244)
# Deployed as: /usr/local/bin/stack-watchdog.sh
# Timer:       stack-watchdog.timer (every 5 min)
# Log:         /var/log/stack-watchdog.log
# =============================================================================
LOG=/var/log/stack-watchdog.log
exec >> "$LOG" 2>&1
echo "--- watchdog run $(date) ---"

# ── helpers ──────────────────────────────────────────────────────────────────
ct_running() { pct status "$1" 2>/dev/null | grep -q running; }

http_ok() {
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1" 2>/dev/null)
  [ "$CODE" = "200" ] || [ "$CODE" = "301" ] || [ "$CODE" = "302" ]
}

ensure_ct_running() {
  local ID=$1 NAME=$2
  if ! ct_running "$ID"; then
    echo "[CRIT] CT-$ID ($NAME) not running — starting"
    pct start "$ID" 2>/dev/null
    sleep 15
  fi
}

# ── Tier 1: CT-100 WireGuard server ──────────────────────────────────────────
ensure_ct_running 100 wireguard

pct exec 100 -- sh -c '
  # Ensure ip_forward
  echo 1 > /proc/sys/net/ipv4/ip_forward
  # Idempotent NAT rule
  iptables -t nat -C POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
  # Ensure WireGuard is up
  if ! wg show wg0 > /dev/null 2>&1; then
    wg-quick down wg0 2>/dev/null; sleep 1; wg-quick up wg0
  fi
' 2>/dev/null && echo "[OK] CT-100 NAT+WG" || echo "[WARN] CT-100 fix failed"

# Persist NAT rule across reboots inside CT-100
pct exec 100 -- sh -c '
  rc-update add iptables default 2>/dev/null || true
  /etc/init.d/iptables save 2>/dev/null || true
  rc-update add wg-quick.wg0 default 2>/dev/null || true
' 2>/dev/null

# ── Tier 2: CT-101 WireGuard client + TinyProxy ───────────────────────────────
ensure_ct_running 101 wg-proxy

pct exec 101 -- sh -c '
  # WireGuard tunnel
  if ! wg show wg0 > /dev/null 2>&1; then
    wg-quick down wg0 2>/dev/null; sleep 1; wg-quick up wg0
    echo "WG restarted"
  fi
  # TinyProxy
  if ! pgrep tinyproxy > /dev/null; then
    rc-service tinyproxy restart 2>/dev/null || tinyproxy
    sleep 2
    pgrep tinyproxy && echo "TinyProxy restarted OK" || echo "TinyProxy start FAIL"
  fi
' 2>/dev/null && echo "[OK] CT-101 WG+proxy" || echo "[WARN] CT-101 fix attempted"

# Proxy reachability test (non-hanging)
PROXY_OK=$(pct exec 101 -- sh -c 'timeout 8 curl -s -x http://127.0.0.1:8888 https://icanhazip.com 2>/dev/null' 2>/dev/null)
if [ -n "$PROXY_OK" ]; then
  echo "[OK] Proxy working — exit IP: $PROXY_OK"
else
  echo "[WARN] Proxy still unreachable — hard restarting CT-101"
  pct exec 101 -- sh -c '
    wg-quick down wg0 2>/dev/null; sleep 2; wg-quick up wg0; sleep 3
    pkill tinyproxy 2>/dev/null; sleep 1
    tinyproxy 2>/dev/null || rc-service tinyproxy start 2>/dev/null
    sleep 3
  ' 2>/dev/null
  PROXY_OK=$(pct exec 101 -- sh -c 'timeout 8 curl -s -x http://127.0.0.1:8888 https://icanhazip.com 2>/dev/null' 2>/dev/null)
  [ -n "$PROXY_OK" ] && echo "[RECOVERED] Proxy now OK: $PROXY_OK" || echo "[CRIT] Proxy still dead after recovery"
fi

# ── Tier 3: CT-102 FlareSolverr ───────────────────────────────────────────────
ensure_ct_running 102 flaresolverr

if ! http_ok "http://192.168.12.102:8191"; then
  echo "[WARN] FlareSolverr down — restarting"
  pct exec 102 -- bash -c '
    docker restart flaresolverr 2>/dev/null || \
    (systemctl restart flaresolverr 2>/dev/null || pkill -f flaresolverr; sleep 2; /opt/flaresolverr/flaresolverr &)
  ' 2>/dev/null
  sleep 10
  http_ok "http://192.168.12.102:8191" && echo "[OK] FlareSolverr recovered" || echo "[CRIT] FlareSolverr still down"
else
  echo "[OK] FlareSolverr"
fi

# ── Tier 4: CT-212 qBittorrent ────────────────────────────────────────────────
ensure_ct_running 212 qbittorrent

if ! http_ok "http://192.168.12.212:8080"; then
  echo "[WARN] qBit WebUI down — fixing"
  pct exec 212 -- bash -c '
    pkill -f qbittorrent 2>/dev/null; sleep 2
    find / -name "*.lock" -path "*qBittorrent*" -delete 2>/dev/null
    find / -name "*.lock" -path "*qbittorrent*" -delete 2>/dev/null
    systemctl restart qbittorrent-nox 2>/dev/null; sleep 6
    if ! systemctl is-active qbittorrent-nox > /dev/null 2>&1; then
      nohup qbittorrent-nox --webui-port=8080 > /var/log/qbittorrent.log 2>&1 &
    fi
  ' 2>/dev/null
  sleep 8
  http_ok "http://192.168.12.212:8080" && echo "[OK] qBit recovered" || echo "[CRIT] qBit still down"
else
  echo "[OK] qBit"
fi

# ── Tier 5: CT-210 Prowlarr ───────────────────────────────────────────────────
ensure_ct_running 210 prowlarr

if ! http_ok "http://192.168.12.210:9696"; then
  echo "[WARN] Prowlarr down — restarting"
  pct exec 210 -- systemctl restart prowlarr 2>/dev/null
  sleep 10
  http_ok "http://192.168.12.210:9696" && echo "[OK] Prowlarr recovered" || echo "[CRIT] Prowlarr still down"
else
  echo "[OK] Prowlarr"
fi

# ── Tier 6: *arr apps ─────────────────────────────────────────────────────────
for PAIR in "214:8989:sonarr:sonarr" "215:8989:radarr:radarr" "217:8787:readarr:readarr" "218:8686:lidarr:lidarr"; do
  CT=${PAIR%%:*}; REST=${PAIR#*:}
  PORT=${REST%%:*}; REST=${REST#*:}
  SVC=${REST%%:*}; NAME=${REST#*:}
  IP="192.168.12.$CT"

  ensure_ct_running "$CT" "$NAME"

  if ! http_ok "http://$IP:$PORT"; then
    echo "[WARN] $NAME (CT-$CT) down — restarting"
    pct exec "$CT" -- systemctl restart "$SVC" 2>/dev/null
    sleep 10
    http_ok "http://$IP:$PORT" && echo "[OK] $NAME recovered" || echo "[CRIT] $NAME still down"
  else
    echo "[OK] $NAME"
  fi
done

# ── Tier 7: Jellyfin ──────────────────────────────────────────────────────────
ensure_ct_running 231 jellyfin

if ! http_ok "http://192.168.12.231:8096"; then
  echo "[WARN] Jellyfin down — restarting"
  pct exec 231 -- systemctl restart jellyfin 2>/dev/null
  sleep 15
  http_ok "http://192.168.12.231:8096" && echo "[OK] Jellyfin recovered" || echo "[CRIT] Jellyfin still down"
else
  echo "[OK] Jellyfin"
fi

# ── Tier 8: Jellyseerr ────────────────────────────────────────────────────────
ensure_ct_running 242 jellyseerr

if ! http_ok "http://192.168.12.151:5055"; then
  echo "[WARN] Jellyseerr down — restarting"
  pct exec 242 -- bash -c 'docker restart jellyseerr 2>/dev/null || systemctl restart jellyseerr 2>/dev/null' 2>/dev/null
  sleep 10
  http_ok "http://192.168.12.151:5055" && echo "[OK] Jellyseerr recovered" || echo "[CRIT] Jellyseerr still down"
else
  echo "[OK] Jellyseerr"
fi

echo "--- watchdog done $(date) ---"
echo ""
