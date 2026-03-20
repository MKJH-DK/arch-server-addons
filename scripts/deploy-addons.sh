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

# Check base server is deployed (verify critical services exist)
log_info "Checking base server..."
if [[ ! -x /usr/local/bin/health-check ]]; then
    log_error "Base server not deployed (health-check not found)."
    log_info "Deploy base first: cd ~/arch-server && ./scripts/deploy.sh"
    exit 1
fi
# Verify critical services are running
for svc in caddy nftables sshd; do
    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        log_warning "Service $svc is not running"
    fi
done
log_success "Base server check passed"

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

# Install Python dependencies required by Ansible modules
log_info "Ensuring Python dependencies are installed..."
pacman -S --needed --noconfirm python-requests &>/dev/null || true

# Find base inventory — derive from this script's location
# If addons repo is at /home/admin/arch-server-addons, base is likely /home/admin/arch-server
SCRIPT_PARENT="$(dirname "$PROJECT_DIR")"
BASE_INVENTORY=""
for candidate in \
    "$SCRIPT_PARENT/arch-server/src/ansible/inventory/hosts.yml" \
    "$HOME/arch-server/src/ansible/inventory/hosts.yml" \
    "/home/admin/arch-server/src/ansible/inventory/hosts.yml" \
    "/root/arch-server/src/ansible/inventory/hosts.yml" \
    "/root/arch/src/ansible/inventory/hosts.yml"; do
    if [[ -f "$candidate" ]]; then
        BASE_INVENTORY="$candidate"
        break
    fi
done

if [[ -z "$BASE_INVENTORY" ]]; then
    log_error "Base Ansible inventory not found"
    log_info "Searched relative to: $SCRIPT_PARENT"
    log_info "Ensure arch-server is cloned next to arch-server-addons"
    exit 1
fi
log_info "Using base inventory: $BASE_INVENTORY"

# Display what will be deployed
log_info "Addon deployment plan:"
echo "  Obsidian Web: ${OBSIDIAN_ENABLED:-false}"
echo "  Backblaze Backup: ${BACKBLAZE_ENABLED:-false}"
echo "  cgit: ${CGIT_ENABLED:-false}"
echo "  Immich: ${IMMICH_ENABLED:-false}"
echo "  CrowdSec: ${CROWDSEC_ENABLED:-false}"
echo "  Ollama: ${OLLAMA_ENABLED:-false}"
echo ""
echo "  AI CLI Tools:"
echo "    Claude Code: ${CLAUDE_CLI_ENABLED:-false}"
echo "    Gemini CLI: ${GEMINI_CLI_ENABLED:-false}"
echo "    ShellGPT: ${SHELLGPT_ENABLED:-false}"
echo "    Codex: ${CODEX_ENABLED:-false}"
echo ""

# Ansible requires UTF-8 locale.
# Pick first available UTF-8 locale from the system.
UTF8_LOCALE="$(locale -a 2>/dev/null | grep -i utf | head -1)"
if [[ -z "$UTF8_LOCALE" ]]; then
    log_error "No UTF-8 locale available. Run: sudo locale-gen"
    exit 1
fi
export LC_ALL="$UTF8_LOCALE"
export LANG="$UTF8_LOCALE"
log_info "Using locale: $UTF8_LOCALE"

# Run addon playbook
log_info "Deploying addons..."
cd "$PROJECT_DIR/ansible"

ansible-playbook -i "$BASE_INVENTORY" \
    playbooks/addons.yml \
    -e "obsidian_enabled=${OBSIDIAN_ENABLED:-false}" \
    -e "obsidian_vault_path=${OBSIDIAN_VAULT_PATH:-/srv/vault}" \
    -e "obsidian_domain=${OBSIDIAN_DOMAIN:-}" \
    -e "obsidian_url_prefix=${OBSIDIAN_URL_PREFIX:-/wiki}" \
    -e "obsidian_syncthing_user=${OBSIDIAN_SYNCTHING_USER:-admin}" \
    -e "obsidian_render_mode=${OBSIDIAN_RENDER_MODE:-quartz}" \
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
    -e "crowdsec_caddy_enabled=${CROWDSEC_CADDY_ENABLED:-true}" \
    -e "ollama_enabled=${OLLAMA_ENABLED:-false}" \
    -e "ollama_bind_address=${OLLAMA_BIND_ADDRESS:-127.0.0.1}" \
    -e "ollama_port=${OLLAMA_PORT:-11434}" \
    -e "ollama_data_path=${OLLAMA_DATA_PATH:-/srv/ollama}" \
    -e "ollama_models_path=${OLLAMA_DATA_PATH:-/srv/ollama}/models" \
    -e "ollama_memory_max=${OLLAMA_MEMORY_MAX:-8G}" \
    -e "ollama_default_models=${OLLAMA_DEFAULT_MODELS:-[]}" \
    -e "ollama_caddy_enabled=${OLLAMA_CADDY_ENABLED:-false}" \
    -e "ollama_domain=${OLLAMA_DOMAIN:-}" \
    -e "ollama_url_prefix=${OLLAMA_URL_PREFIX:-/ollama}" \
    -e "claude_cli_enabled=${CLAUDE_CLI_ENABLED:-false}" \
    -e "gemini_cli_enabled=${GEMINI_CLI_ENABLED:-false}" \
    -e "shellgpt_enabled=${SHELLGPT_ENABLED:-false}" \
    -e "codex_enabled=${CODEX_ENABLED:-false}"

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

    if [[ "${OLLAMA_ENABLED:-false}" == "true" ]]; then
        echo "  Ollama:"
        echo "    - API: http://${OLLAMA_BIND_ADDRESS:-127.0.0.1}:${OLLAMA_PORT:-11434}"
        echo "    - Data: ${OLLAMA_DATA_PATH:-/srv/ollama}"
        echo "    - Pull model: ollama pull llama3.1:8b"
        echo "    - Chat: ollama run llama3.1:8b"
        echo "    - Status: ollama-manage status"
    fi

    # AI CLI Tools
    ai_tools_shown=false
    for tool_var in CLAUDE_CLI_ENABLED GEMINI_CLI_ENABLED SHELLGPT_ENABLED CODEX_ENABLED; do
        if [[ "${!tool_var:-false}" == "true" ]]; then
            if [[ "$ai_tools_shown" == "false" ]]; then
                echo ""
                echo "  AI CLI Tools:"
                ai_tools_shown=true
            fi
            case "$tool_var" in
                CLAUDE_CLI_ENABLED) echo "    - Claude Code: claude --help (kræver ANTHROPIC_API_KEY)" ;;
                GEMINI_CLI_ENABLED) echo "    - Gemini CLI: gemini --help (kræver GEMINI_API_KEY)" ;;
                SHELLGPT_ENABLED) echo "    - ShellGPT: sgpt --help (kræver OPENAI_API_KEY)" ;;
                CODEX_ENABLED) echo "    - Codex: codex --help (kræver OPENAI_API_KEY)" ;;
            esac
        fi
    done

    echo ""
    log_success "All done! Run '/usr/local/bin/health-check' to verify system status"
else
    log_error "Addon deployment failed"
    exit 1
fi
