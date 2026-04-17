#!/usr/bin/env bash
# ============================================================
# Phase 7 — Orchestrator
# Deploys: Recyclarr, Jellystat, Decluttarr, Uptime Kuma,
#          Threadfin, Dispatcharr
#
# Run on Proxmox host (Tiamat) as root:
#   bash /opt/homelab-media-stack/scripts/deploy-phase7.sh
#
# Env flags (all optional):
#   PHASE7_DESTROY_STALE=1  destroy stopped CT-244/245/277 before install
#   ONLY="recyclarr jellystat"  run only the listed services
#   SKIP="dispatcharr"          skip listed services
#   FORCE_RECREATE=1            destroy+rebuild the CTs that will deploy
# ============================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/phase7-common.sh"

ALL=(recyclarr jellystat decluttarr uptimekuma threadfin dispatcharr)
PICK=()

if [ -n "${ONLY:-}" ]; then
  for s in $ONLY; do PICK+=("$s"); done
else
  PICK=("${ALL[@]}")
fi
if [ -n "${SKIP:-}" ]; then
  NEW=()
  for s in "${PICK[@]}"; do
    keep=1
    for sk in $SKIP; do [ "$s" = "$sk" ] && keep=0; done
    [ $keep -eq 1 ] && NEW+=("$s")
  done
  PICK=("${NEW[@]}")
fi

p7_step "Phase 7 → deploying: ${PICK[*]}"
p7_require_pve

# Optional one-time cleanup of legacy Plex-only shells
if [ "${PHASE7_DESTROY_STALE:-0}" = "1" ]; then
  p7_info "Destroying stale CTs 244 (tautulli), 245 (kometa), 277 (recyclarr shell) ..."
  for ctid in 244 245 277; do p7_ct_destroy_if_exists "$ctid" || true; done
fi

FAILED=()
for svc in "${PICK[@]}"; do
  script="${SCRIPT_DIR}/deploy-${svc}.sh"
  [ -x "$script" ] || chmod +x "$script" 2>/dev/null || true
  if [ ! -f "$script" ]; then
    p7_error "Missing $script"; FAILED+=("$svc"); continue
  fi
  p7_step "▶ ${svc}"
  if bash "$script"; then
    p7_ok "${svc} completed."
  else
    p7_error "${svc} FAILED."
    FAILED+=("$svc")
  fi
done

p7_step "Phase 7 summary"
if [ ${#FAILED[@]} -eq 0 ]; then
  p7_ok "All services deployed."
else
  p7_error "Failed: ${FAILED[*]}"
  exit 1
fi

echo
echo "HTTP endpoints:"
printf '  %-14s %s\n' \
  "recyclarr"   "(no UI — cron daily 03:45)" \
  "decluttarr"  "(no UI — journalctl -u decluttarr)" \
  "jellystat"   "http://192.168.12.247:3000" \
  "uptime-kuma" "http://192.168.12.248:3001" \
  "threadfin"   "http://192.168.12.234:34400/web" \
  "dispatcharr" "http://192.168.12.235:9191"
echo
echo "Via Traefik (after copying infrastructure/traefik/dynamic/phase7.yml to CT-103):"
printf '  http://%s.tiamat.local\n' jellystat uptime threadfin dispatcharr
