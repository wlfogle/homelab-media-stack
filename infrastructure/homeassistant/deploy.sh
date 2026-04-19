#!/usr/bin/env bash
# ============================================================
# Deploy Home Assistant configs to VM-500 (HAOS @ 192.168.12.250)
#
# Prerequisites:
#   - SSH Add-on installed in HAOS (port 22222)
#   - SSH key added to HAOS authorized_keys
#   - secrets.yaml created from secrets.yaml.example
#
# Usage:  bash infrastructure/homeassistant/deploy.sh
#         bash infrastructure/homeassistant/deploy.sh --dry-run
# ============================================================
set -euo pipefail

HA_HOST="192.168.12.250"
HA_PORT="22222"
HA_USER="root"
HA_CONFIG_DIR="/config"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=false

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$SRC_DIR/secrets.yaml" ]] || \
  die "secrets.yaml not found. Copy secrets.yaml.example → secrets.yaml and fill in values."

SSH_OPTS="-p $HA_PORT -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"

if $DRY_RUN; then
  log "DRY RUN — files that would be copied:"
  for f in configuration.yaml binary_sensor.yaml sensors.yaml \
            rest_commands.yaml scripts.yaml automations.yaml \
            intent_script.yaml secrets.yaml; do
    echo "  $SRC_DIR/$f → $HA_USER@$HA_HOST:$HA_CONFIG_DIR/$f"
  done
  exit 0
fi

log "Connecting to HAOS VM-500 @ $HA_HOST:$HA_PORT..."

# Backup existing config
log "Backing up existing config..."
# shellcheck disable=SC2029
ssh $SSH_OPTS "$HA_USER@$HA_HOST" \
  "mkdir -p /config/backups && cp -r /config/*.yaml /config/backups/backup-\$(date +%Y%m%d-%H%M%S)/ 2>/dev/null || true"

# Copy config files
log "Copying config files..."
for f in configuration.yaml binary_sensor.yaml sensors.yaml \
          rest_commands.yaml scripts.yaml automations.yaml \
          intent_script.yaml secrets.yaml; do
  if [[ -f "$SRC_DIR/$f" ]]; then
    scp $SSH_OPTS "$SRC_DIR/$f" "$HA_USER@$HA_HOST:$HA_CONFIG_DIR/$f"
    log "  ✓ $f"
  fi
done

# Validate config
log "Validating configuration..."
ssh $SSH_OPTS "$HA_USER@$HA_HOST" \
  "ha core check" && log "  ✓ Config valid" || die "Config validation failed — check HA logs"

# Restart HA core
log "Restarting Home Assistant core..."
ssh $SSH_OPTS "$HA_USER@$HA_HOST" "ha core restart"

log "Done. Monitor at http://$HA_HOST:8123"
