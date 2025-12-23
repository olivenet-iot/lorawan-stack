#!/bin/bash
# =============================================================================
# Olivenet TTS - Restore Script
# =============================================================================
# Restore The Things Stack from backup archive
#
# Features:
#   - Pre-restore backup (safety)
#   - PostgreSQL restore
#   - Redis restore
#   - Config restore
#   - Dry-run mode
#   - Interactive confirmation
#   - Selective restore
#
# Exit codes:
#   0 = Success
#   1 = Partial failure
#   2 = Complete failure
#
# Usage:
#   ./restore.sh backup-20250120-143022.tar.gz
#   ./restore.sh --dry-run backup-20250120-143022.tar.gz
#   ./restore.sh --db-only backup-20250120-143022.tar.gz
# =============================================================================

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# Script-specific Configuration
# =============================================================================

RESTORE_TYPE="full"
RESTORE_COMPONENTS=("postgres" "redis" "config" "blob")
DRY_RUN=false
SKIP_PRE_BACKUP=false
ARCHIVE_PATH=""

# =============================================================================
# Help
# =============================================================================

show_help() {
    show_help_header "restore.sh" "Restore The Things Stack from backup"

    cat << EOF
${BOLD}Usage:${NC}
    $0 [OPTIONS] <backup-archive.tar.gz>

${BOLD}Options:${NC}
    --dry-run           Show what would be restored without making changes
    --db-only           Restore databases only (PostgreSQL + Redis)
    --config-only       Restore config files only
    --blob-only         Restore blob storage only
    --skip-pre-backup   Skip pre-restore backup (not recommended)
    --list              List contents of backup archive

EOF
    show_common_options

    cat << EOF
${BOLD}Environment Variables:${NC}
    DEPLOY_DIR          Deployment directory (default: /opt/olivenet-tts)
    POSTGRES_CONTAINER  PostgreSQL container name (default: olivenet-postgres)
    REDIS_CONTAINER     Redis container name (default: olivenet-redis)

${BOLD}Examples:${NC}
    $0 backup-20250120-143022.tar.gz           # Full restore
    $0 --dry-run backup-20250120-143022.tar.gz # Preview restore
    $0 --db-only backup-20250120-143022.tar.gz # Databases only
    $0 --list backup-20250120-143022.tar.gz    # List archive contents

${BOLD}Warning:${NC}
    This will overwrite existing data! A pre-restore backup is created
    automatically unless --skip-pre-backup is specified.

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
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --db-only)
                RESTORE_TYPE="db"
                RESTORE_COMPONENTS=("postgres" "redis")
                shift
                ;;
            --config-only)
                RESTORE_TYPE="config"
                RESTORE_COMPONENTS=("config")
                shift
                ;;
            --blob-only)
                RESTORE_TYPE="blob"
                RESTORE_COMPONENTS=("blob")
                shift
                ;;
            --skip-pre-backup)
                SKIP_PRE_BACKUP=true
                shift
                ;;
            --list)
                LIST_MODE=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 2
                ;;
            *)
                ARCHIVE_PATH="$1"
                shift
                ;;
        esac
    done
}

# =============================================================================
# Utility Functions
# =============================================================================

list_archive() {
    local archive="$1"

    echo -e "${BOLD}Archive contents:${NC}"
    tar -tvf "$archive" | head -50

    local total
    total=$(tar -tzf "$archive" | wc -l)
    if [[ $total -gt 50 ]]; then
        echo "... and $((total - 50)) more files"
    fi

    echo ""
    echo -e "${BOLD}Components:${NC}"

    if tar -tzf "$archive" | grep -q "postgres.sql"; then
        local size
        size=$(tar -tvf "$archive" | grep "postgres.sql" | awk '{print $3}')
        echo "  - PostgreSQL database ($(format_size "$size"))"
    fi

    if tar -tzf "$archive" | grep -q "dump.rdb"; then
        local size
        size=$(tar -tvf "$archive" | grep "dump.rdb" | awk '{print $3}')
        echo "  - Redis snapshot ($(format_size "$size"))"
    fi

    local config_count
    config_count=$(tar -tzf "$archive" | grep -c "^config/" || echo "0")
    if [[ $config_count -gt 0 ]]; then
        echo "  - Config files ($config_count files)"
    fi

    local blob_count
    blob_count=$(tar -tzf "$archive" | grep -c "^blob/" || echo "0")
    if [[ $blob_count -gt 0 ]]; then
        echo "  - Blob storage ($blob_count files)"
    fi
}

create_pre_backup() {
    log_info "Creating pre-restore backup..."

    local timestamp
    timestamp=$(get_timestamp)
    local pre_backup="$BACKUP_DIR/pre-restore-${timestamp}.tar.gz"

    # Run backup script
    if "${SCRIPT_DIR}/backup.sh" --backup-dir "$BACKUP_DIR"; then
        log_success "Pre-restore backup created"
        return 0
    else
        log_error "Pre-restore backup failed"
        return 1
    fi
}

# =============================================================================
# Restore Functions
# =============================================================================

restore_postgres() {
    local temp_dir="$1"
    local dump_file="$temp_dir/postgres.sql"

    if [[ ! -f "$dump_file" ]]; then
        log_warn "No PostgreSQL dump found in archive"
        return 0
    fi

    log_info "Restoring PostgreSQL..."

    if [[ "$DRY_RUN" == "true" ]]; then
        local size
        size=$(get_file_size "$dump_file")
        log_info "[DRY-RUN] Would restore PostgreSQL database ($(format_size "$size"))"
        return 0
    fi

    if ! require_container "$POSTGRES_CONTAINER"; then
        return 1
    fi

    # Get database credentials
    local db_user
    local db_name
    db_user=$(docker inspect "$POSTGRES_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep POSTGRES_USER | cut -d= -f2)
    db_name=$(docker inspect "$POSTGRES_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep POSTGRES_DB | cut -d= -f2)

    db_user="${db_user:-ttn}"
    db_name="${db_name:-ttn_lorawan}"

    # Drop and recreate database
    log_debug "Dropping existing database..."
    docker exec "$POSTGRES_CONTAINER" psql -U "$db_user" -c "DROP DATABASE IF EXISTS ${db_name};" postgres 2>/dev/null || true
    docker exec "$POSTGRES_CONTAINER" psql -U "$db_user" -c "CREATE DATABASE ${db_name};" postgres 2>/dev/null || true

    # Restore dump
    if cat "$dump_file" | docker exec -i "$POSTGRES_CONTAINER" psql -U "$db_user" -d "$db_name" > /dev/null 2>&1; then
        log_success "PostgreSQL restored successfully"
        return 0
    else
        log_error "PostgreSQL restore failed"
        return 1
    fi
}

restore_redis() {
    local temp_dir="$1"
    local rdb_file="$temp_dir/dump.rdb"

    if [[ ! -f "$rdb_file" ]]; then
        log_warn "No Redis dump found in archive"
        return 0
    fi

    log_info "Restoring Redis..."

    if [[ "$DRY_RUN" == "true" ]]; then
        local size
        size=$(get_file_size "$rdb_file")
        log_info "[DRY-RUN] Would restore Redis snapshot ($(format_size "$size"))"
        return 0
    fi

    if ! require_container "$REDIS_CONTAINER"; then
        return 1
    fi

    # Stop Redis, copy RDB, restart
    log_debug "Stopping Redis..."
    docker stop "$REDIS_CONTAINER" > /dev/null 2>&1

    # Copy RDB file to volume
    docker cp "$rdb_file" "$REDIS_CONTAINER":/data/dump.rdb 2>/dev/null || {
        # Container stopped, use volume directly
        local redis_volume
        redis_volume=$(docker inspect "$REDIS_CONTAINER" --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}')

        if [[ -n "$redis_volume" ]]; then
            docker run --rm -v "${redis_volume}:/data" -v "$rdb_file:/dump.rdb:ro" alpine \
                cp /dump.rdb /data/dump.rdb
        fi
    }

    # Start Redis
    docker start "$REDIS_CONTAINER" > /dev/null 2>&1

    # Wait for Redis to be ready
    sleep 3

    if docker_container_running "$REDIS_CONTAINER"; then
        log_success "Redis restored successfully"
        return 0
    else
        log_error "Redis restore failed - container not running"
        return 1
    fi
}

restore_config() {
    local temp_dir="$1"
    local config_dir="$temp_dir/config"

    if [[ ! -d "$config_dir" ]]; then
        log_warn "No config directory found in archive"
        return 0
    fi

    log_info "Restoring config files..."

    local file_count
    file_count=$(find "$config_dir" -type f | wc -l)

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would restore $file_count config files to $DEPLOY_DIR/deploy/olivenet/"
        find "$config_dir" -type f -exec echo "  {}" \;
        return 0
    fi

    # Create target directory
    mkdir -p "$DEPLOY_DIR/deploy/olivenet/config"

    # Copy files
    cp -r "$config_dir/"* "$DEPLOY_DIR/deploy/olivenet/config/" 2>/dev/null || true

    # Handle .env file specially (if exists)
    if [[ -f "$config_dir/.env" ]]; then
        cp "$config_dir/.env" "$DEPLOY_DIR/deploy/olivenet/"
    fi

    log_success "Config files restored ($file_count files)"
    return 0
}

restore_blob() {
    local temp_dir="$1"
    local blob_dir="$temp_dir/blob"

    if [[ ! -d "$blob_dir" ]]; then
        log_warn "No blob directory found in archive"
        return 0
    fi

    log_info "Restoring blob storage..."

    local file_count
    file_count=$(find "$blob_dir" -type f | wc -l)

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would restore $file_count blob files"
        return 0
    fi

    # Get blob volume
    local blob_volume
    blob_volume=$(docker volume ls --format '{{.Name}}' | grep -E 'blob' | head -1)

    if [[ -n "$blob_volume" ]]; then
        # Restore to volume using temporary container
        docker run --rm -v "${blob_volume}:/target" -v "$blob_dir:/source:ro" alpine \
            sh -c "rm -rf /target/* && cp -r /source/* /target/ 2>/dev/null || true"

        log_success "Blob storage restored ($file_count files)"
    else
        log_warn "No blob volume found, skipping blob restore"
    fi

    return 0
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Initialize logging
    ensure_log_dir
    export LOG_FILE="$LOG_DIR/restore.log"

    # Check archive path
    if [[ -z "$ARCHIVE_PATH" ]]; then
        # Try to use latest backup
        if [[ -L "$BACKUP_DIR/.latest" ]]; then
            ARCHIVE_PATH=$(readlink -f "$BACKUP_DIR/.latest")
            log_info "Using latest backup: $ARCHIVE_PATH"
        else
            log_error "No backup archive specified"
            show_help
            exit 2
        fi
    fi

    # Resolve relative path
    if [[ ! "$ARCHIVE_PATH" = /* ]]; then
        ARCHIVE_PATH="$(pwd)/$ARCHIVE_PATH"
    fi

    # Check if archive exists
    if [[ ! -f "$ARCHIVE_PATH" ]]; then
        log_error "Archive not found: $ARCHIVE_PATH"
        exit 2
    fi

    # List mode
    if [[ "${LIST_MODE:-false}" == "true" ]]; then
        list_archive "$ARCHIVE_PATH"
        exit 0
    fi

    log_info "=========================================="
    log_info "Starting $RESTORE_TYPE restore"
    log_info "Archive: $ARCHIVE_PATH"
    log_info "=========================================="

    # Confirmation
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        echo -e "${YELLOW}WARNING: This will overwrite existing data!${NC}"
        echo ""

        if ! confirm "Continue with restore?"; then
            log_info "Restore cancelled"
            exit 0
        fi
    fi

    # Acquire lock
    if ! acquire_lock "restore"; then
        exit 2
    fi

    # Validate environment
    require_docker

    # Create pre-restore backup
    if [[ "$DRY_RUN" != "true" && "$SKIP_PRE_BACKUP" != "true" ]]; then
        ensure_backup_dir
        create_pre_backup || {
            if ! confirm "Pre-backup failed. Continue anyway?"; then
                exit 2
            fi
        }
    fi

    # Extract archive to temp directory
    TEMP_DIR=$(mktemp -d)
    log_debug "Extracting to: $TEMP_DIR"

    if ! tar -xzf "$ARCHIVE_PATH" -C "$TEMP_DIR"; then
        log_error "Failed to extract archive"
        rm -rf "$TEMP_DIR"
        exit 2
    fi

    # Track success/failure
    local total=0
    local failed=0

    # Run restores
    for component in "${RESTORE_COMPONENTS[@]}"; do
        total=$((total + 1))
        case $component in
            postgres)
                restore_postgres "$TEMP_DIR" || failed=$((failed + 1))
                ;;
            redis)
                restore_redis "$TEMP_DIR" || failed=$((failed + 1))
                ;;
            config)
                restore_config "$TEMP_DIR" || failed=$((failed + 1))
                ;;
            blob)
                restore_blob "$TEMP_DIR" || failed=$((failed + 1))
                ;;
        esac
    done

    # Cleanup temp directory
    rm -rf "$TEMP_DIR"

    # Restart services if needed (not in dry-run)
    if [[ "$DRY_RUN" != "true" && $failed -eq 0 ]]; then
        log_info "Restarting TTS stack..."
        if docker_container_running "$STACK_CONTAINER"; then
            docker restart "$STACK_CONTAINER" > /dev/null 2>&1 || true
        fi
    fi

    # Summary
    log_info "=========================================="
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry-run completed - no changes made"
        exit 0
    elif [[ $failed -eq 0 ]]; then
        log_success "Restore completed successfully"
        exit 0
    elif [[ $failed -lt $total ]]; then
        log_warn "Restore completed with warnings ($failed/$total components had issues)"
        exit 1
    else
        log_error "Restore failed"
        exit 2
    fi
}

main "$@"
