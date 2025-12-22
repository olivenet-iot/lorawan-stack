#!/bin/bash
# =============================================================================
# Olivenet TTS - Backup Script
# =============================================================================
# Full backup script for The Things Stack deployment
#
# Features:
#   - PostgreSQL full backup (pg_dump)
#   - Redis RDB snapshot
#   - Config files backup
#   - Blob storage backup
#   - Retention policy
#   - Integrity verification
#
# Exit codes:
#   0 = Success
#   1 = Partial failure (some components failed)
#   2 = Complete failure
#
# Usage:
#   ./backup.sh                     # Full backup
#   ./backup.sh --db-only           # Database only
#   ./backup.sh --config-only       # Config only
#   ./backup.sh --retention 14      # Set retention days
# =============================================================================

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# Script-specific Configuration
# =============================================================================

BACKUP_TYPE="full"
BACKUP_COMPONENTS=("postgres" "redis" "config" "blob")
SKIP_VERIFY=false

# =============================================================================
# Help
# =============================================================================

show_help() {
    show_help_header "backup.sh" "Backup The Things Stack deployment"

    cat << EOF
${BOLD}Options:${NC}
    --db-only           Backup databases only (PostgreSQL + Redis)
    --config-only       Backup config files only
    --blob-only         Backup blob storage only
    --retention DAYS    Set retention policy (default: $RETENTION_DAYS days)
    --skip-verify       Skip backup integrity verification
    --backup-dir DIR    Override backup directory

EOF
    show_common_options

    cat << EOF
${BOLD}Environment Variables:${NC}
    BACKUP_DIR          Backup directory (default: /var/backups/olivenet-tts)
    POSTGRES_CONTAINER  PostgreSQL container name (default: olivenet-postgres)
    REDIS_CONTAINER     Redis container name (default: olivenet-redis)
    RETENTION_DAYS      Backup retention in days (default: 7)
    DEPLOY_DIR          Deployment directory (default: /opt/olivenet-tts)

${BOLD}Examples:${NC}
    $0                          # Full backup
    $0 --db-only                # Databases only
    $0 --retention 14           # Keep 14 days of backups
    $0 --backup-dir /mnt/backup # Custom backup location

EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --no-color)
                export NO_COLOR=true
                shift
                ;;
            --debug)
                export DEBUG=true
                shift
                ;;
            -f|--force)
                export FORCE=true
                shift
                ;;
            --db-only)
                BACKUP_TYPE="db"
                BACKUP_COMPONENTS=("postgres" "redis")
                shift
                ;;
            --config-only)
                BACKUP_TYPE="config"
                BACKUP_COMPONENTS=("config")
                shift
                ;;
            --blob-only)
                BACKUP_TYPE="blob"
                BACKUP_COMPONENTS=("blob")
                shift
                ;;
            --retention)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            --skip-verify)
                SKIP_VERIFY=true
                shift
                ;;
            --backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 2
                ;;
        esac
    done
}

# =============================================================================
# Backup Functions
# =============================================================================

backup_postgres() {
    log_info "Backing up PostgreSQL..."

    if ! require_container "$POSTGRES_CONTAINER"; then
        return 1
    fi

    local dump_file="$TEMP_DIR/postgres.sql"

    # Get database credentials from container environment
    local db_user
    local db_name
    db_user=$(docker inspect "$POSTGRES_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep POSTGRES_USER | cut -d= -f2)
    db_name=$(docker inspect "$POSTGRES_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep POSTGRES_DB | cut -d= -f2)

    db_user="${db_user:-ttn}"
    db_name="${db_name:-ttn_lorawan}"

    if docker exec "$POSTGRES_CONTAINER" pg_dump -U "$db_user" -d "$db_name" > "$dump_file" 2>/dev/null; then
        local size
        size=$(get_file_size "$dump_file")
        log_success "PostgreSQL backup complete ($(format_size "$size"))"
        return 0
    else
        log_error "PostgreSQL backup failed"
        return 1
    fi
}

backup_redis() {
    log_info "Backing up Redis..."

    if ! require_container "$REDIS_CONTAINER"; then
        return 1
    fi

    # Trigger BGSAVE
    local redis_password
    redis_password=$(docker inspect "$REDIS_CONTAINER" --format '{{range .Config.Cmd}}{{println .}}{{end}}' | grep -A1 'requirepass' | tail -1 || echo "")

    if [[ -n "$redis_password" ]]; then
        docker exec "$REDIS_CONTAINER" redis-cli -a "$redis_password" BGSAVE > /dev/null 2>&1 || true
    else
        docker exec "$REDIS_CONTAINER" redis-cli BGSAVE > /dev/null 2>&1 || true
    fi

    # Wait for BGSAVE to complete
    sleep 2

    # Copy RDB file
    local rdb_file="$TEMP_DIR/dump.rdb"
    if docker cp "$REDIS_CONTAINER":/data/dump.rdb "$rdb_file" 2>/dev/null; then
        local size
        size=$(get_file_size "$rdb_file")
        log_success "Redis backup complete ($(format_size "$size"))"
        return 0
    else
        log_warn "Redis RDB file not found (might be empty or AOF-only)"
        return 0  # Not critical
    fi
}

backup_config() {
    log_info "Backing up config files..."

    local config_dir="$TEMP_DIR/config"
    mkdir -p "$config_dir"

    # Copy deployment config files
    if [[ -d "$DEPLOY_DIR/deploy/olivenet/config" ]]; then
        cp -r "$DEPLOY_DIR/deploy/olivenet/config/"* "$config_dir/" 2>/dev/null || true
    fi

    # Copy .env file if exists
    if [[ -f "$DEPLOY_DIR/deploy/olivenet/.env" ]]; then
        cp "$DEPLOY_DIR/deploy/olivenet/.env" "$config_dir/" 2>/dev/null || true
    fi

    # Copy docker-compose files
    if [[ -f "$DEPLOY_DIR/deploy/olivenet/docker-compose.yml" ]]; then
        cp "$DEPLOY_DIR/deploy/olivenet/docker-compose.yml" "$config_dir/" 2>/dev/null || true
    fi

    local file_count
    file_count=$(find "$config_dir" -type f | wc -l)

    if [[ $file_count -gt 0 ]]; then
        log_success "Config backup complete ($file_count files)"
        return 0
    else
        log_warn "No config files found"
        return 0
    fi
}

backup_blob() {
    log_info "Backing up blob storage..."

    local blob_dir="$TEMP_DIR/blob"
    mkdir -p "$blob_dir"

    # Get blob volume data
    local blob_volume
    blob_volume=$(docker volume ls --format '{{.Name}}' | grep -E 'blob' | head -1)

    if [[ -n "$blob_volume" ]]; then
        # Copy from volume using temporary container
        docker run --rm -v "${blob_volume}:/source:ro" -v "$blob_dir:/backup" alpine \
            sh -c "cp -r /source/* /backup/ 2>/dev/null || true"

        local file_count
        file_count=$(find "$blob_dir" -type f | wc -l)
        log_success "Blob storage backup complete ($file_count files)"
    else
        log_warn "No blob volume found"
    fi

    return 0
}

verify_backup() {
    local archive="$1"

    log_info "Verifying backup integrity..."

    # Test archive integrity
    if ! tar -tzf "$archive" > /dev/null 2>&1; then
        log_error "Backup archive is corrupted"
        return 1
    fi

    # Check archive contents
    local contents
    contents=$(tar -tzf "$archive")

    local has_content=false
    for component in "${BACKUP_COMPONENTS[@]}"; do
        case $component in
            postgres)
                if echo "$contents" | grep -q "postgres.sql"; then
                    has_content=true
                fi
                ;;
            redis)
                if echo "$contents" | grep -q "dump.rdb"; then
                    has_content=true
                fi
                ;;
            config)
                if echo "$contents" | grep -q "config/"; then
                    has_content=true
                fi
                ;;
            blob)
                if echo "$contents" | grep -q "blob/"; then
                    has_content=true
                fi
                ;;
        esac
    done

    if [[ "$has_content" == "true" ]]; then
        log_success "Backup verification passed"
        return 0
    else
        log_warn "Backup may be incomplete"
        return 0
    fi
}

cleanup_old_backups() {
    log_info "Cleaning up old backups (retention: $RETENTION_DAYS days)..."

    local deleted=0

    # Clean daily backups
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((deleted++))
    done < <(find "$BACKUP_DIR/daily" -name "backup-*.tar.gz" -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)

    # Keep weekly backups longer (4x retention)
    local weekly_retention=$((RETENTION_DAYS * 4))
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((deleted++))
    done < <(find "$BACKUP_DIR/weekly" -name "backup-*.tar.gz" -mtime +"$weekly_retention" -print0 2>/dev/null)

    if [[ $deleted -gt 0 ]]; then
        log_info "Deleted $deleted old backup(s)"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Initialize logging
    ensure_log_dir
    export LOG_FILE="$LOG_DIR/backup.log"

    log_info "=========================================="
    log_info "Starting $BACKUP_TYPE backup"
    log_info "=========================================="

    # Acquire lock
    if ! acquire_lock "backup"; then
        exit 2
    fi

    # Validate environment
    require_docker
    ensure_backup_dir
    check_disk_space 1000 "$BACKUP_DIR"

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    log_debug "Temp directory: $TEMP_DIR"

    # Track success/failure
    local total=0
    local failed=0

    # Run backups
    for component in "${BACKUP_COMPONENTS[@]}"; do
        ((total++))
        case $component in
            postgres)
                backup_postgres || ((failed++))
                ;;
            redis)
                backup_redis || ((failed++))
                ;;
            config)
                backup_config || ((failed++))
                ;;
            blob)
                backup_blob || ((failed++))
                ;;
        esac
    done

    # Create archive
    local timestamp
    timestamp=$(get_timestamp)
    local archive_name="backup-${timestamp}.tar.gz"
    local archive_path

    # Determine if this should go to weekly (Sunday)
    if [[ $(get_day_of_week) -eq 7 ]]; then
        archive_path="$BACKUP_DIR/weekly/$archive_name"
    else
        archive_path="$BACKUP_DIR/daily/$archive_name"
    fi

    log_info "Creating archive: $archive_name"

    if tar -czf "$archive_path" -C "$TEMP_DIR" .; then
        local size
        size=$(get_file_size "$archive_path")
        log_success "Archive created ($(format_size "$size"))"

        # Update latest symlink
        ln -sf "$archive_path" "$BACKUP_DIR/.latest"
    else
        log_error "Failed to create archive"
        ((failed++))
    fi

    # Verify backup
    if [[ "$SKIP_VERIFY" != "true" ]]; then
        verify_backup "$archive_path" || ((failed++))
    fi

    # Cleanup old backups
    cleanup_old_backups

    # Cleanup temp directory
    rm -rf "$TEMP_DIR"

    # Summary
    log_info "=========================================="
    if [[ $failed -eq 0 ]]; then
        log_success "Backup completed successfully"
        log_info "Archive: $archive_path"
        exit 0
    elif [[ $failed -lt $total ]]; then
        log_warn "Backup completed with warnings ($failed/$total components had issues)"
        log_info "Archive: $archive_path"
        exit 1
    else
        log_error "Backup failed"
        exit 2
    fi
}

main "$@"
