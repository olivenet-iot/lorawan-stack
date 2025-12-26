#!/bin/bash
# =============================================================================
# Olivenet TTS - Status Page Generator
# =============================================================================
# Generates a static HTML status page
#
# Features:
#   - All component status
#   - 24-hour uptime history
#   - Last backup time
#   - Auto-refresh
#
# Usage:
#   ./status-page.sh                           # Generate page
#   ./status-page.sh --output /var/www/status  # Custom output
# =============================================================================

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# Configuration
# =============================================================================

# Output directory - use /var/www if writable, otherwise /tmp
if [[ -w "/var/www" ]]; then
    OUTPUT_DIR="${OUTPUT_DIR:-/var/www/olivenet-tts-status}"
else
    OUTPUT_DIR="${OUTPUT_DIR:-/tmp/olivenet-tts-status}"
fi
OUTPUT_FILE="${OUTPUT_DIR}/index.html"
HEALTH_SCRIPT="${SCRIPT_DIR}/health-check.sh"

# History file - use /var/run if writable, otherwise /tmp
if [[ -w "/var/run" ]]; then
    HISTORY_FILE="${HISTORY_FILE:-/var/run/olivenet-tts-status-history.json}"
else
    HISTORY_FILE="${HISTORY_FILE:-/tmp/olivenet-tts-status-history.json}"
fi
REFRESH_INTERVAL=60

# =============================================================================
# Help
# =============================================================================

show_help() {
    show_help_header "status-page.sh" "Generate static status page"

    cat << EOF
${BOLD}Options:${NC}
    --output DIR        Output directory (default: $OUTPUT_DIR)
    --refresh SECONDS   Auto-refresh interval (default: $REFRESH_INTERVAL)

EOF
    show_common_options

    cat << EOF
${BOLD}Examples:${NC}
    $0                                  # Generate to default location
    $0 --output /var/www/html/status    # Custom location

EOF
}

# =============================================================================
# Functions
# =============================================================================

get_health_data() {
    if [[ -x "$HEALTH_SCRIPT" ]]; then
        "$HEALTH_SCRIPT" --json 2>/dev/null
    else
        echo '{"status":"unknown","checks":{}}'
    fi
}

get_last_backup() {
    local backup_link="/var/backups/olivenet-tts/.latest"

    if [[ -L "$backup_link" ]]; then
        local backup_file
        backup_file=$(readlink -f "$backup_link" 2>/dev/null)
        if [[ -f "$backup_file" ]]; then
            local backup_time
            backup_time=$(stat -c %Y "$backup_file" 2>/dev/null || stat -f %m "$backup_file" 2>/dev/null)
            local backup_size
            backup_size=$(stat -c %s "$backup_file" 2>/dev/null || stat -f %z "$backup_file" 2>/dev/null)

            echo "{\"time\":$backup_time,\"size\":$backup_size,\"file\":\"$(basename "$backup_file")\"}"
            return
        fi
    fi

    echo '{"time":0,"size":0,"file":"none"}'
}

update_history() {
    local current_status="$1"
    local timestamp
    timestamp=$(date +%s)

    # Initialize history file if needed
    if [[ ! -f "$HISTORY_FILE" ]]; then
        echo '{"entries":[]}' > "$HISTORY_FILE"
    fi

    # Add new entry (keep last 24 hours = 1440 entries at 1 min interval)
    local new_entry="{\"time\":$timestamp,\"status\":\"$current_status\"}"

    # Simple append and trim (not perfect JSON handling but works)
    local entries
    entries=$(cat "$HISTORY_FILE" | grep -o '\[.*\]' | sed 's/^\[//' | sed 's/\]$//' || :)

    if [[ -n "$entries" ]]; then
        entries="$entries,$new_entry"
    else
        entries="$new_entry"
    fi

    # Keep only last 1440 entries
    local entry_count
    entry_count=$(echo "$entries" | tr ',' '\n' | wc -l)

    if [[ $entry_count -gt 1440 ]]; then
        entries=$(echo "$entries" | tr ',' '\n' | tail -1440 | tr '\n' ',' | sed 's/,$//')
    fi

    echo "{\"entries\":[$entries]}" > "$HISTORY_FILE"
}

calculate_uptime() {
    if [[ ! -f "$HISTORY_FILE" ]]; then
        echo "100"
        return
    fi

    local total
    local healthy

    total=$(grep -o '"status"' "$HISTORY_FILE" | wc -l || :)
    healthy=$(grep -o '"status":"healthy"' "$HISTORY_FILE" | wc -l || :)

    if [[ $total -eq 0 ]]; then
        echo "100"
    else
        echo "$((healthy * 100 / total))"
    fi
}

generate_html() {
    local health_data="$1"
    local backup_data="$2"
    local uptime="$3"

    local status
    status=$(echo "$health_data" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || :)

    local status_color
    local status_icon
    local status_text

    case $status in
        healthy)
            status_color="#22c55e"
            status_icon="✓"
            status_text="All Systems Operational"
            ;;
        degraded)
            status_color="#f59e0b"
            status_icon="⚠"
            status_text="Partial Outage"
            ;;
        critical)
            status_color="#ef4444"
            status_icon="✗"
            status_text="Major Outage"
            ;;
        *)
            status_color="#6b7280"
            status_icon="?"
            status_text="Unknown Status"
            ;;
    esac

    local backup_time
    backup_time=$(echo "$backup_data" | grep -o '"time":[0-9]*' | head -1 | cut -d: -f2 || :)
    local backup_ago=""

    if [[ "$backup_time" != "0" && -n "$backup_time" ]]; then
        local now
        now=$(date +%s)
        local diff=$((now - backup_time))
        local hours=$((diff / 3600))
        local mins=$(((diff % 3600) / 60))

        if [[ $hours -gt 0 ]]; then
            backup_ago="${hours}h ${mins}m ago"
        else
            backup_ago="${mins}m ago"
        fi
    else
        backup_ago="Never"
    fi

    cat << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="$REFRESH_INTERVAL">
    <title>Olivenet TTS Status</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
            min-height: 100vh;
            padding: 2rem;
        }
        .container { max-width: 800px; margin: 0 auto; }
        header { text-align: center; margin-bottom: 2rem; }
        h1 { font-size: 1.5rem; font-weight: 600; margin-bottom: 0.5rem; }
        .status-badge {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.75rem 1.5rem;
            border-radius: 9999px;
            font-size: 1.125rem;
            font-weight: 600;
            background: ${status_color}20;
            color: ${status_color};
            border: 2px solid ${status_color};
        }
        .status-icon { font-size: 1.25rem; }
        .card {
            background: #1e293b;
            border-radius: 0.75rem;
            padding: 1.5rem;
            margin-bottom: 1rem;
        }
        .card-title {
            font-size: 0.875rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            color: #94a3b8;
            margin-bottom: 1rem;
        }
        .metric {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0.75rem 0;
            border-bottom: 1px solid #334155;
        }
        .metric:last-child { border-bottom: none; }
        .metric-name { color: #cbd5e1; }
        .metric-value { font-weight: 600; }
        .metric-ok { color: #22c55e; }
        .metric-warn { color: #f59e0b; }
        .metric-error { color: #ef4444; }
        .uptime-bar {
            height: 8px;
            background: #334155;
            border-radius: 4px;
            overflow: hidden;
            margin-top: 0.5rem;
        }
        .uptime-fill {
            height: 100%;
            background: linear-gradient(90deg, #22c55e, #16a34a);
            border-radius: 4px;
        }
        .uptime-value {
            font-size: 2rem;
            font-weight: 700;
            color: #22c55e;
        }
        .timestamp {
            text-align: center;
            color: #64748b;
            font-size: 0.875rem;
            margin-top: 2rem;
        }
        footer {
            text-align: center;
            margin-top: 2rem;
            color: #475569;
            font-size: 0.75rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Olivenet TTS Status</h1>
            <div class="status-badge">
                <span class="status-icon">${status_icon}</span>
                <span>${status_text}</span>
            </div>
        </header>

        <div class="card">
            <div class="card-title">System Components</div>
EOF

    # Parse and display each check
    local checks
    checks=$(echo "$health_data" | grep -o '"checks":{[^}]*}' | sed 's/"checks"://' || :)

    for component in stack postgres redis disk memory docker ssl; do
        local check_data
        check_data=$(echo "$health_data" | grep -o "\"$component\":{[^}]*}" || :)

        local check_status="unknown"
        local check_message="-"

        if [[ -n "$check_data" ]]; then
            check_status=$(echo "$check_data" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || :)
            check_message=$(echo "$check_data" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4 || :)
        fi

        local status_class="metric-ok"
        local status_symbol="✓"

        case $check_status in
            ok) status_class="metric-ok"; status_symbol="✓" ;;
            warning) status_class="metric-warn"; status_symbol="⚠" ;;
            error) status_class="metric-error"; status_symbol="✗" ;;
            skip) status_class=""; status_symbol="○" ;;
            *) status_class=""; status_symbol="?" ;;
        esac

        cat << EOF
            <div class="metric">
                <span class="metric-name">${component^}</span>
                <span class="metric-value ${status_class}">${status_symbol} ${check_message}</span>
            </div>
EOF
    done

    cat << EOF
        </div>

        <div class="card">
            <div class="card-title">24-Hour Uptime</div>
            <div class="uptime-value">${uptime}%</div>
            <div class="uptime-bar">
                <div class="uptime-fill" style="width: ${uptime}%"></div>
            </div>
        </div>

        <div class="card">
            <div class="card-title">Last Backup</div>
            <div class="metric">
                <span class="metric-name">Time</span>
                <span class="metric-value">${backup_ago}</span>
            </div>
        </div>

        <div class="timestamp">
            Last updated: $(date '+%Y-%m-%d %H:%M:%S %Z')
        </div>

        <footer>
            Olivenet TTS Monitoring &bull; Auto-refreshes every ${REFRESH_INTERVAL} seconds
        </footer>
    </div>
</body>
</html>
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
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
            --output)
                OUTPUT_DIR="$2"
                OUTPUT_FILE="${OUTPUT_DIR}/index.html"
                shift 2
                ;;
            --refresh)
                REFRESH_INTERVAL="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 2
                ;;
        esac
    done

    # Ensure output directory exists
    mkdir -p "$OUTPUT_DIR"

    log_info "Generating status page..."

    # Get data
    local health_data
    health_data=$(get_health_data)

    local backup_data
    backup_data=$(get_last_backup)

    # Update history
    local current_status
    current_status=$(echo "$health_data" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || :)
    update_history "$current_status"

    # Calculate uptime
    local uptime
    uptime=$(calculate_uptime)

    # Generate HTML
    generate_html "$health_data" "$backup_data" "$uptime" > "$OUTPUT_FILE"

    log_success "Status page generated: $OUTPUT_FILE"
}

main "$@"
