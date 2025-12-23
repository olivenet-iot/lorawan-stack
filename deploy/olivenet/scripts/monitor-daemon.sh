#!/bin/bash
# =============================================================================
# Olivenet TTS - Monitor Daemon
# =============================================================================
# Continuous monitoring daemon for The Things Stack
#
# Features:
#   - Periodic health checks (60 second interval)
#   - Alert on consecutive failures
#   - Recovery notification
#   - Status logging
#
# Usage:
#   ./monitor-daemon.sh start    # Start daemon
#   ./monitor-daemon.sh stop     # Stop daemon
#   ./monitor-daemon.sh status   # Check status
#   ./monitor-daemon.sh restart  # Restart daemon
# =============================================================================

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# Configuration
# =============================================================================

DAEMON_NAME="olivenet-tts-monitor"
PID_FILE="/var/run/${DAEMON_NAME}.pid"
STATUS_FILE="/var/run/${DAEMON_NAME}.status"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
FAILURE_THRESHOLD="${FAILURE_THRESHOLD:-3}"

# Alert configuration
ALERT_SCRIPT="${SCRIPT_DIR}/alert.sh"
HEALTH_SCRIPT="${SCRIPT_DIR}/health-check.sh"

# =============================================================================
# Help
# =============================================================================

show_help() {
    show_help_header "monitor-daemon.sh" "TTS monitoring daemon"

    cat << EOF
${BOLD}Commands:${NC}
    start       Start the monitoring daemon
    stop        Stop the monitoring daemon
    status      Show daemon status
    restart     Restart the daemon
    run         Run in foreground (for debugging)

${BOLD}Options:${NC}
    --interval SECONDS  Check interval (default: $CHECK_INTERVAL)
    --threshold N       Failures before alert (default: $FAILURE_THRESHOLD)

EOF
    show_common_options

    cat << EOF
${BOLD}Environment Variables:${NC}
    CHECK_INTERVAL      Health check interval in seconds
    FAILURE_THRESHOLD   Consecutive failures before alerting

${BOLD}Examples:${NC}
    $0 start                      # Start daemon
    $0 start --interval 30        # 30 second interval
    $0 status                     # Check if running

EOF
}

# =============================================================================
# Daemon Functions
# =============================================================================

is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

get_pid() {
    if [[ -f "$PID_FILE" ]]; then
        cat "$PID_FILE"
    else
        echo ""
    fi
}

start_daemon() {
    if is_running; then
        log_warn "Daemon is already running (PID: $(get_pid))"
        return 1
    fi

    log_info "Starting $DAEMON_NAME..."

    # Start daemon process
    nohup "$0" run > /dev/null 2>&1 &
    local pid=$!

    # Wait a moment to ensure it started
    sleep 2

    if kill -0 "$pid" 2>/dev/null; then
        echo "$pid" > "$PID_FILE"
        log_success "Daemon started (PID: $pid)"
        return 0
    else
        log_error "Daemon failed to start"
        return 1
    fi
}

stop_daemon() {
    if ! is_running; then
        log_warn "Daemon is not running"
        return 0
    fi

    local pid
    pid=$(get_pid)
    log_info "Stopping $DAEMON_NAME (PID: $pid)..."

    # Send SIGTERM
    kill "$pid" 2>/dev/null

    # Wait for process to stop
    local count=0
    while kill -0 "$pid" 2>/dev/null && [[ $count -lt 10 ]]; do
        sleep 1
        count=$((count + 1))
    done

    # Force kill if still running
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null
    fi

    rm -f "$PID_FILE" "$STATUS_FILE"
    log_success "Daemon stopped"
    return 0
}

show_status() {
    if is_running; then
        local pid
        pid=$(get_pid)
        echo -e "${GREEN}●${NC} $DAEMON_NAME is running (PID: $pid)"

        if [[ -f "$STATUS_FILE" ]]; then
            echo ""
            echo "Last status:"
            cat "$STATUS_FILE"
        fi

        return 0
    else
        echo -e "${RED}○${NC} $DAEMON_NAME is not running"
        return 1
    fi
}

# =============================================================================
# Main Loop
# =============================================================================

run_monitor() {
    log_info "Monitor daemon starting..."
    log_info "Check interval: ${CHECK_INTERVAL}s"
    log_info "Failure threshold: $FAILURE_THRESHOLD"

    # Write PID for foreground mode
    echo $$ > "$PID_FILE"

    # State tracking
    local consecutive_failures=0
    local last_status="unknown"
    local is_alerting=false

    # Cleanup on exit
    cleanup_daemon() {
        log_info "Monitor daemon stopping..."
        rm -f "$PID_FILE" "$STATUS_FILE"
        exit 0
    }
    trap cleanup_daemon EXIT INT TERM

    # Main loop
    while true; do
        local check_time
        check_time=$(date '+%Y-%m-%d %H:%M:%S')

        # Run health check
        local result
        local exit_code
        result=$("$HEALTH_SCRIPT" --json 2>/dev/null)
        exit_code=$?

        # Parse status
        local status
        status=$(echo "$result" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

        # Update status file
        cat > "$STATUS_FILE" << EOF
Last Check: $check_time
Status: $status
Exit Code: $exit_code
Consecutive Failures: $consecutive_failures
EOF

        log_debug "Health check: status=$status, exit_code=$exit_code"

        # Handle status changes
        if [[ $exit_code -eq 2 ]]; then
            # Critical failure
            consecutive_failures=$((consecutive_failures + 1))
            log_warn "Health check failed ($consecutive_failures/$FAILURE_THRESHOLD)"

            if [[ $consecutive_failures -ge $FAILURE_THRESHOLD && "$is_alerting" != "true" ]]; then
                is_alerting=true
                log_error "Failure threshold reached, sending alert"

                # Send alert
                if [[ -x "$ALERT_SCRIPT" ]]; then
                    local alert_msg="TTS Health Check Failed

Status: CRITICAL
Consecutive Failures: $consecutive_failures
Time: $check_time
Host: $(hostname)

Details:
$result"
                    "$ALERT_SCRIPT" --all "$alert_msg" 2>/dev/null || true
                fi
            fi
        else
            # Healthy or warning
            if [[ $consecutive_failures -gt 0 ]]; then
                log_info "Health check recovered (was $consecutive_failures failures)"

                # Send recovery alert if we were alerting
                if [[ "$is_alerting" == "true" ]]; then
                    is_alerting=false

                    if [[ -x "$ALERT_SCRIPT" ]]; then
                        local recovery_msg="TTS Health Check Recovered

Status: $status
Time: $check_time
Host: $(hostname)
Previous Failures: $consecutive_failures"
                        "$ALERT_SCRIPT" --all "$recovery_msg" 2>/dev/null || true
                    fi
                fi
            fi

            consecutive_failures=0
        fi

        last_status="$status"

        # Wait for next check
        sleep "$CHECK_INTERVAL"
    done
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    local command=""

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
            --interval)
                CHECK_INTERVAL="$2"
                shift 2
                ;;
            --threshold)
                FAILURE_THRESHOLD="$2"
                shift 2
                ;;
            start|stop|status|restart|run)
                command="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 2
                ;;
        esac
    done

    # Default command
    if [[ -z "$command" ]]; then
        show_help
        exit 0
    fi

    echo "$command"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local command
    command=$(parse_args "$@")

    case $command in
        start)
            start_daemon
            ;;
        stop)
            stop_daemon
            ;;
        status)
            show_status
            ;;
        restart)
            stop_daemon
            sleep 1
            start_daemon
            ;;
        run)
            run_monitor
            ;;
        *)
            log_error "Unknown command: $command"
            exit 2
            ;;
    esac
}

main "$@"
