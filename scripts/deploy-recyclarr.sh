#!/usr/bin/env bash
# ============================================================
# Phase 7 — Recyclarr (CT-245 @ 192.168.12.245)
#
# Syncs TRaSH-guide quality profiles / custom formats to Sonarr
# (CT-214) and Radarr (CT-215). Native binary install + daily cron.
#
# Run on Proxmox host (Tiamat):
#   bash /opt/homelab-media-stack/scripts/deploy-recyclarr.sh
#
# Env:
#   DESTROY_STALE=1  destroy stopped CT-245 (kometa) + CT-277 (shell)
#   FORCE_RECREATE=1 destroy CT-245 if it exists even without DESTROY_STALE
# ============================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/phase7-common.sh"

CTID=245
HOSTNAME=recyclarr
IP=192.168.12.245

p7_step "Recyclarr → CT-${CTID} @ ${IP}"
p7_require_pve

if [ "${DESTROY_STALE:-0}" = "1" ]; then
  p7_ct_destroy_if_exists 277   # empty shell per README
  p7_ct_destroy_if_exists 245   # stopped kometa
elif [ "${FORCE_RECREATE:-0}" = "1" ]; then
  p7_ct_destroy_if_exists "$CTID"
fi

p7_ct_create "$CTID" "$HOSTNAME" "$IP" 1 512 2
p7_ct_start_and_wait "$CTID"

p7_info "Discovering *arr API keys from CT-214 / CT-215 ..."
SONARR_KEY=$(p7_arr_key 214 sonarr || true)
RADARR_KEY=$(p7_arr_key 215 radarr || true)
[ -n "$SONARR_KEY" ] || { p7_error "could not read Sonarr API key from CT-214"; exit 1; }
[ -n "$RADARR_KEY" ] || { p7_error "could not read Radarr API key from CT-215"; exit 1; }

p7_info "Installing base packages in CT-${CTID}..."
p7_ct_run "$CTID" <<'BASH'
apt-get update -qq
apt-get install -y --no-install-recommends -qq curl ca-certificates xz-utils cron tzdata
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo America/New_York > /etc/timezone
BASH

p7_info "Fetching latest recyclarr release ..."
p7_ct_run "$CTID" <<'BASH'
set -Eeuo pipefail
ASSET_URL=$(curl -fsSL https://api.github.com/repos/recyclarr/recyclarr/releases/latest \
  | grep -oE '"browser_download_url":\s*"[^"]+recyclarr-linux-x64\.tar\.xz"' \
  | head -n1 | cut -d'"' -f4)
[ -n "$ASSET_URL" ] || { echo "recyclarr asset not found"; exit 1; }
curl -fsSL "$ASSET_URL" -o /tmp/recyclarr.tar.xz
tar -xJf /tmp/recyclarr.tar.xz -C /usr/local/bin
rm -f /tmp/recyclarr.tar.xz
chmod +x /usr/local/bin/recyclarr
recyclarr --version
mkdir -p /root/.config/recyclarr/{configs,includes}
BASH

p7_info "Writing recyclarr.yml with TRaSH templates pre-wired to Sonarr/Radarr ..."
p7_ct_write "$CTID" /root/.config/recyclarr/recyclarr.yml 0600 root:root <<YAML
# Managed by scripts/deploy-recyclarr.sh — edit-in-place OK, keys are auto.
# TRaSH-guide templates: https://recyclarr.dev/wiki/yaml/templates/
sonarr:
  main:
    base_url: http://192.168.12.214:8989
    api_key: ${SONARR_KEY}
    include:
      - template: sonarr-quality-definition-series
      - template: sonarr-v4-quality-profile-web-1080p
      - template: sonarr-v4-custom-formats-web-1080p
    quality_profiles:
      - name: WEB-1080p
        reset_unmatched_scores:
          enabled: true
    delete_old_custom_formats: true

radarr:
  main:
    base_url: http://192.168.12.225:7878
    api_key: ${RADARR_KEY}
    include:
      - template: radarr-quality-definition-movie
      - template: radarr-quality-profile-hd-bluray-web
      - template: radarr-custom-formats-hd-bluray-web
    quality_profiles:
      - name: HD Bluray + WEB
        reset_unmatched_scores:
          enabled: true
    delete_old_custom_formats: true
YAML

p7_info "Installing daily sync cron ..."
p7_ct_write "$CTID" /etc/cron.d/recyclarr 0644 root:root <<'CRON'
# Run recyclarr sync daily at 03:45
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
45 3 * * * root /usr/local/bin/recyclarr sync >> /root/.config/recyclarr/sync.log 2>&1
CRON

p7_info "Running initial dry-run sync ..."
if p7_ct_run "$CTID" <<'BASH'
systemctl enable --now cron >/dev/null 2>&1 || service cron start >/dev/null 2>&1
recyclarr sync --preview 2>&1 | tail -n 30 || true
BASH
then
  p7_ok "Recyclarr deployed on CT-${CTID}. First real sync: cron nightly 03:45 (or run 'pct exec ${CTID} -- recyclarr sync' now)."
else
  p7_warn "Preview sync had warnings — review 'pct exec ${CTID} -- recyclarr sync --preview' output."
fi
