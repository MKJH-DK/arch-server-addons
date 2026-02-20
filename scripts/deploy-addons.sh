#!/bin/bash
# Deploy addons til Arch Server
# Forudsætning: Base-server er deployed via /root/arch/scripts/deploy.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Find project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Check base server health
log_info "Checking base server health..."
if ! /usr/local/bin/health-check --json 2>/dev/null | grep -q '"status":"pass"'; then
    log_error "Base server health check failed. Deploy base first."
    log_info "Run: cd /root/arch && ./scripts/deploy.sh"
    exit 1
fi
log_success "Base server health check passed"

# Check if addon config exists
ADDON_CONFIG="$PROJECT_DIR/config/addons.env"
if [[ ! -f "$ADDON_CONFIG" ]]; then
    log_error "Addon config not found: $ADDON_CONFIG"
    log_info "Copy config/addons.env.example to config/addons.env and configure"
    exit 1
fi

# Source addon configuration
log_info "Loading addon configuration..."
source "$ADDON_CONFIG"

# Validate required variables
validate_config() {
    local errors=0
    
    if [[ "${OBSIDIAN_ENABLED:-false}" == "true" ]]; then
        if [[ -z "${OBSIDIAN_VAULT_PATH:-}" ]]; then
            log_error "OBSIDIAN_VAULT_PATH is required when OBSIDIAN_ENABLED=true"
            ((errors++))
        fi
    fi
    
    if [[ "${BACKBLAZE_ENABLED:-false}" == "true" ]]; then
        if [[ -z "${BACKUP_B2_BUCKET:-}" ]]; then
            log_error "BACKUP_B2_BUCKET is required when BACKBLAZE_ENABLED=true"
            ((errors++))
        fi
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Configuration validation failed"
        exit 1
    fi
}

validate_config
log_success "Configuration validation passed"

# Check Ansible availability
if ! command -v ansible-playbook &> /dev/null; then
    log_error "ansible-playbook not found. Install Ansible first."
    exit 1
fi

# Check base inventory exists
BASE_INVENTORY="/root/arch/src/ansible/inventory/hosts.yml"
if [[ ! -f "$BASE_INVENTORY" ]]; then
    log_error "Base Ansible inventory not found: $BASE_INVENTORY"
    log_info "Ensure base server is deployed first"
    exit 1
fi

# Display what will be deployed
log_info "Addon deployment plan:"
echo "  Obsidian Web: ${OBSIDIAN_ENABLED:-false}"
echo "  Backblaze Backup: ${BACKBLAZE_ENABLED:-false}"
echo "  cgit: ${CGIT_ENABLED:-false}"
echo "  Immich: ${IMMICH_ENABLED:-false}"
echo "  CrowdSec: ${CROWDSEC_ENABLED:-false}"
echo ""

# Run addon playbook
log_info "Deploying addons..."
cd "$PROJECT_DIR/ansible"

ansible-playbook -i "$BASE_INVENTORY" \
    playbooks/addons.yml \
    -e "obsidian_enabled=${OBSIDIAN_ENABLED:-false}" \
    -e "obsidian_vault_path=${OBSIDIAN_VAULT_PATH:-/srv/obsidian/vault}" \
    -e "obsidian_domain=${OBSIDIAN_DOMAIN:-}" \
    -e "obsidian_url_prefix=${OBSIDIAN_URL_PREFIX:-/wiki}" \
    -e "obsidian_syncthing_user=${OBSIDIAN_SYNCTHING_USER:-root}" \
    -e "obsidian_render_mode=${OBSIDIAN_RENDER_MODE:-client}" \
    -e "backblaze_enabled=${BACKBLAZE_ENABLED:-false}" \
    -e "backup_b2_bucket=${BACKUP_B2_BUCKET:-}" \
    -e "backup_schedule=${BACKUP_SCHEDULE:-daily}" \
    -e "backup_retention_days=${BACKUP_RETENTION_DAYS:-30}" \
    -e "backup_encrypt=${BACKUP_ENCRYPT:-true}" \
    -e "backup_paths=${BACKUP_PATHS:-/srv /etc/caddy}" \
    -e "cgit_enabled=${CGIT_ENABLED:-false}" \
    -e "cgit_title=${CGIT_TITLE:-My Git Repos}" \
    -e "cgit_repo_path=${CGIT_REPO_PATH:-/srv/git}" \
    -e "cgit_url_prefix=${CGIT_URL_PREFIX:-/git}" \
    -e "immich_enabled=${IMMICH_ENABLED:-false}" \
    -e "immich_domain=${IMMICH_DOMAIN:-}" \
    -e "immich_url_prefix=${IMMICH_URL_PREFIX:-/photos}" \
    -e "immich_data_path=${IMMICH_DATA_PATH:-/srv/immich}" \
    -e "immich_admin_email=${IMMICH_ADMIN_EMAIL:-admin@example.com}" \
    -e "immich_version=${IMMICH_VERSION:-latest}" \
    -e "crowdsec_enabled=${CROWDSEC_ENABLED:-false}" \
    -e "crowdsec_domain=${CROWDSEC_DOMAIN:-}" \
    -e "crowdsec_url_prefix=${CROWDSEC_URL_PREFIX:-/security}" \
    -e "crowdsec_data_path=${CROWDSEC_DATA_PATH:-/srv/crowdsec}" \
    -e "crowdsec_config_path=${CROWDSEC_CONFIG_PATH:-/etc/crowdsec}" \
    -e "crowdsec_log_path=${CROWDSEC_LOG_PATH:-/var/log/crowdsec}" \
    -e "crowdsec_agent_port=${CROWDSEC_AGENT_PORT:-8080}" \
    -e "crowdsec_api_port=${CROWDSEC_API_PORT:-8081}" \
    -e "crowdsec_firewall_enabled=${CROWDSEC_FIREWALL_ENABLED:-true}" \
    -e "crowdsec_caddy_enabled=${CROWDSEC_CADDY_ENABLED:-true}"

if [[ $? -eq 0 ]]; then
    log_success "Addon deployment completed successfully"
    
    # Post-deployment information
    echo ""
    log_info "Post-deployment information:"
    
    if [[ "${OBSIDIAN_ENABLED:-false}" == "true" ]]; then
        echo "  Obsidian Web:"
        echo "    - URL: http://localhost${OBSIDIAN_URL_PREFIX:-/wiki}/"
        echo "    - Syncthing UI: http://localhost:8384"
        echo "    - Vault path: ${OBSIDIAN_VAULT_PATH:-/srv/obsidian/vault}"
        echo "    - Next: Pair your devices via Syncthing UI"
    fi
    
    if [[ "${BACKBLAZE_ENABLED:-false}" == "true" ]]; then
        echo "  Backblaze Backup:"
        echo "    - Run: rclone config to configure B2 credentials"
        echo "    - Timer: systemctl status server-backup.timer"
    fi
    
    if [[ "${CGIT_ENABLED:-false}" == "true" ]]; then
        echo "  cgit:"
        echo "    - URL: http://localhost${CGIT_URL_PREFIX:-/git}/"
        echo "    - Repo path: ${CGIT_REPO_PATH:-/srv/git}"
    fi
    
    if [[ "${IMMICH_ENABLED:-false}" == "true" ]]; then
        echo "  Immich:"
        echo "    - URL: http://localhost${IMMICH_URL_PREFIX:-/photos}/"
        echo "    - Data path: ${IMMICH_DATA_PATH:-/srv/immich}"
        echo "    - Admin: ${IMMICH_ADMIN_EMAIL:-admin@example.com}"
    fi
    
    if [[ "${CROWDSEC_ENABLED:-false}" == "true" ]]; then
        echo "  CrowdSec:"
        echo "    - URL: http://localhost${CROWDSEC_URL_PREFIX:-/security}/"
        echo "    - Data path: ${CROWDSEC_DATA_PATH:-/srv/crowdsec}"
        echo "    - Agent port: ${CROWDSEC_AGENT_PORT:-8080}"
        echo "    - API port: ${CROWDSEC_API_PORT:-8081}"
    fi
    
    echo ""
    log_success "All done! Run '/usr/local/bin/health-check' to verify system status"
else
    log_error "Addon deployment failed"
    exit 1
fi
