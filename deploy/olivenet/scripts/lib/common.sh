#!/bin/bash
# =============================================================================
# Olivenet TTS - Common Library Functions
# =============================================================================
# Shared functions for all operational scripts
# Source this file: source "$(dirname "$0")/lib/common.sh"
# =============================================================================

# Strict mode
set -euo pipefail

# =============================================================================
# Safe Arithmetic Functions (for use with set -e)
# =============================================================================
# ((var++)) fails when var=0 due to set -e. These functions are safe alternatives.

incr() {
    local var_name="$1"
    eval "$var_name=\$((\$var_name + 1))"
}

# =============================================================================
# Configuration
# =============================================================================

# Auto-detect deploy dir from script location
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEPLOY_DIR="${DEPLOY_DIR:-$(dirname "$(dirname "$_SCRIPT_DIR")")}"
export BACKUP_DIR="${BACKUP_DIR:-/var/backups/olivenet-tts}"
export LOG_DIR="${LOG_DIR:-/var/log/olivenet-tts}"
export POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-olivenet-postgres}"
export REDIS_CONTAINER="${REDIS_CONTAINER:-olivenet-redis}"
export STACK_CONTAINER="${STACK_CONTAINER:-olivenet-stack}"
export RETENTION_DAYS="${RETENTION_DAYS:-7}"

# Colors (disabled with --no-color)
export NO_COLOR="${NO_COLOR:-false}"

# =============================================================================
# Color Functions
# =============================================================================

_color() {
    if [[ "$NO_COLOR" == "true" ]]; then
        echo -n ""
    else
        echo -n "$1"
    fi
}

RED=$(_color '\033[0;31m')
GREEN=$(_color '\033[0;32m')
YELLOW=$(_color '\033[0;33m')
BLUE=$(_color '\033[0;34m')
CYAN=$(_color '\033[0;36m')
NC=$(_color '\033[0m') # No Color
BOLD=$(_color '\033[1m')

# =============================================================================
# Logging Functions
# =============================================================================

_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    echo -e "${BLUE}[$(_timestamp)]${NC} ${GREEN}[INFO]${NC} $*"
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[$(_timestamp)] [INFO] $*" >> "$LOG_FILE"
    fi
}

log_warn() {
    echo -e "${BLUE}[$(_timestamp)]${NC} ${YELLOW}[WARN]${NC} $*" >&2
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[$(_timestamp)] [WARN] $*" >> "$LOG_FILE"
    fi
}

log_error() {
    echo -e "${BLUE}[$(_timestamp)]${NC} ${RED}[ERROR]${NC} $*" >&2
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[$(_timestamp)] [ERROR] $*" >> "$LOG_FILE"
    fi
}

log_success() {
    echo -e "${BLUE}[$(_timestamp)]${NC} ${GREEN}[SUCCESS]${NC} $*"
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[$(_timestamp)] [SUCCESS] $*" >> "$LOG_FILE"
    fi
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[$(_timestamp)]${NC} ${CYAN}[DEBUG]${NC} $*"
        if [[ -n "${LOG_FILE:-}" ]]; then
            echo "[$(_timestamp)] [DEBUG] $*" >> "$LOG_FILE"
        fi
    fi
}

# =============================================================================
# Directory Functions
# =============================================================================

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_debug "Created directory: $dir"
    fi
}

ensure_log_dir() {
    ensure_dir "$LOG_DIR"
}

ensure_backup_dir() {
    ensure_dir "$BACKUP_DIR"
    ensure_dir "$BACKUP_DIR/daily"
    ensure_dir "$BACKUP_DIR/weekly"
    ensure_dir "$BACKUP_DIR/logs"
}

# =============================================================================
# Docker Functions
# =============================================================================

docker_container_exists() {
    local container="$1"
    docker ps -a --format '{{.Names}}' | grep -q "^${container}$"
}

docker_container_running() {
    local container="$1"
    docker ps --format '{{.Names}}' | grep -q "^${container}$"
}

docker_exec() {
    local container="$1"
    shift
    docker exec "$container" "$@"
}

docker_exec_it() {
    local container="$1"
    shift
    docker exec -it "$container" "$@"
}

# =============================================================================
# Validation Functions
# =============================================================================

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

require_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
}

require_container() {
    local container="$1"
    if ! docker_container_running "$container"; then
        log_error "Container '$container' is not running"
        return 1
    fi
}

check_disk_space() {
    local required_mb="${1:-1000}"
    local path="${2:-$BACKUP_DIR}"
    local available_mb

    available_mb=$(df -m "$path" | awk 'NR==2 {print $4}')

    if [[ $available_mb -lt $required_mb ]]; then
        log_error "Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
        return 1
    fi
    log_debug "Disk space OK: ${available_mb}MB available"
}

# =============================================================================
# Lock File Functions
# =============================================================================

LOCK_FILE=""

acquire_lock() {
    local lock_name="$1"
    LOCK_FILE="/var/run/olivenet-tts-${lock_name}.lock"

    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid=$(cat "$LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_error "Another instance is running (PID: $pid)"
            return 1
        else
            log_warn "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi

    echo $$ > "$LOCK_FILE"
    log_debug "Lock acquired: $LOCK_FILE"
}

release_lock() {
    if [[ -n "$LOCK_FILE" && -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log_debug "Lock released: $LOCK_FILE"
    fi
}

# =============================================================================
# Cleanup Function
# =============================================================================

cleanup() {
    local exit_code=$?
    release_lock
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with code: $exit_code"
    fi
    exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# =============================================================================
# File Size Functions
# =============================================================================

format_size() {
    local bytes="$1"
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024))KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# =============================================================================
# Date Functions
# =============================================================================

get_timestamp() {
    date '+%Y%m%d-%H%M%S'
}

get_date() {
    date '+%Y%m%d'
}

get_day_of_week() {
    date '+%u'  # 1=Monday, 7=Sunday
}

# =============================================================================
# Confirmation Functions
# =============================================================================

confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-n}"

    if [[ "${FORCE:-false}" == "true" ]]; then
        return 0
    fi

    local yn
    if [[ "$default" == "y" ]]; then
        read -r -p "$prompt [Y/n] " yn
        yn="${yn:-y}"
    else
        read -r -p "$prompt [y/N] " yn
        yn="${yn:-n}"
    fi

    case "$yn" in
        [Yy]* ) return 0;;
        * ) return 1;;
    esac
}

# =============================================================================
# JSON Output Functions
# =============================================================================

json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

# =============================================================================
# Help Function Template
# =============================================================================

show_help_header() {
    local script_name="$1"
    local description="$2"

    cat << EOF
${BOLD}$script_name${NC}
$description

${BOLD}Usage:${NC}
    $script_name [OPTIONS]

EOF
}

show_common_options() {
    cat << EOF
${BOLD}Common Options:${NC}
    -h, --help          Show this help message
    --no-color          Disable colored output
    --debug             Enable debug output
    -f, --force         Skip confirmation prompts

EOF
}
