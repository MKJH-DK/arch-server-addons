#!/bin/bash
# Check Syncthing sync status for Obsidian addon

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ADDON_CONFIG="$PROJECT_DIR/config/addons.env"

if [[ ! -f "$ADDON_CONFIG" ]]; then
    log_error "Addon config not found: $ADDON_CONFIG"
    exit 1
fi

source "$ADDON_CONFIG"

# Check if Obsidian addon is enabled
if [[ "${OBSIDIAN_ENABLED:-false}" != "true" ]]; then
    log_warning "Obsidian addon is not enabled"
    exit 0
fi

SYNCTHING_USER="${OBSIDIAN_SYNCTHING_USER:-root}"
VAULT_PATH="${OBSIDIAN_VAULT_PATH:-/srv/obsidian/vault}"

log_info "Checking Syncthing status for user: $SYNCTHING_USER"

# Check if Syncthing service is running
if ! systemctl --user -"$SYNCTHING_USER" is-active --quiet syncthing; then
    log_error "Syncthing service is not running"
    log_info "Start with: systemctl --user -root enable --now syncthing"
    exit 1
fi

log_success "Syncthing service is running"

# Check API availability
API_URL="http://127.0.0.1:8384/rest/system/status"
if ! curl -s "$API_URL" > /dev/null; then
    log_error "Cannot reach Syncthing API at $API_URL"
    exit 1
fi

# Get sync status
log_info "Retrieving sync status..."

# Get folder status
FOLDER_STATUS=$(curl -s "http://127.0.0.1:8384/rest/folder/status?folder=default" 2>/dev/null || echo "")

if [[ -z "$FOLDER_STATUS" ]]; then
    log_warning "Could not retrieve folder status - folder might not be configured"
    log_info "Configure Syncthing via web UI: http://localhost:8384"
    exit 1
fi

# Parse JSON (basic parsing without jq)
GLOBAL_BYTES=$(echo "$FOLDER_STATUS" | grep -o '"globalBytes":[0-9]*' | cut -d: -f2)
LOCAL_BYTES=$(echo "$FOLDER_STATUS" | grep -o '"localBytes":[0-9]*' | cut -d: -f2)
NEED_BYTES=$(echo "$FOLDER_STATUS" | grep -o '"needBytes":[0-9]*' | cut -d: -f2)

if [[ -z "$GLOBAL_BYTES" ]]; then
    log_error "Could not parse sync status"
    exit 1
fi

# Calculate sync percentage
if [[ "$GLOBAL_BYTES" -gt 0 ]]; then
    SYNCED_BYTES=$((GLOBAL_BYTES - NEED_BYTES))
    SYNC_PERCENT=$(( (SYNCED_BYTES * 100) / GLOBAL_BYTES ))
else
    SYNC_PERCENT=100
fi

# Display status
echo ""
echo "Sync Status:"
echo "  Total size: $(( GLOBAL_BYTES / 1024 / 1024 )) MB"
echo "  Synced: $(( SYNCED_BYTES / 1024 / 1024 )) MB"
echo "  Remaining: $(( NEED_BYTES / 1024 / 1024 )) MB"
echo "  Progress: ${SYNC_PERCENT}%"

if [[ "$SYNC_PERCENT" -eq 100 ]]; then
    log_success "Vault is fully synced"
else
    log_warning "Sync in progress (${SYNC_PERCENT}%)"
fi

# Check vault directory
if [[ -d "$VAULT_PATH" ]]; then
    FILE_COUNT=$(find "$VAULT_PATH" -name "*.md" | wc -l)
    echo "  Markdown files: $FILE_COUNT"
else
    log_warning "Vault directory not found: $VAULT_PATH"
fi

# Show connected devices
echo ""
echo "Connected Devices:"
DEVICE_STATUS=$(curl -s "http://127.0.0.1:8384/rest/system/connections" 2>/dev/null || echo "")

if [[ -n "$DEVICE_STATUS" ]]; then
    # Extract device names and status
    echo "$DEVICE_STATUS" | grep -o '"connected":true' | wc -l | xargs -I {} echo "  Connected devices: {}"
else
    log_warning "Could not retrieve device status"
fi

echo ""
log_info "Web UI: http://localhost:8384"
