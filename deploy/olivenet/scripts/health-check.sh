#!/bin/bash
# =============================================================================
# Olivenet TTS - Health Check Script
# =============================================================================
# Comprehensive health check for The Things Stack deployment
#
# Checks:
#   - TTS Stack /healthz endpoint
#   - PostgreSQL connectivity
#   - Redis connectivity
#   - Disk usage
#   - Memory usage
#   - Docker container status
#   - SSL certificate expiry
#
# Exit codes:
#   0 = Healthy
#   1 = Degraded (warnings)
#   2 = Critical (failures)
#
# Usage:
#   ./health-check.sh              # All checks
#   ./health-check.sh --json       # JSON output
#   ./health-check.sh --component stack  # Specific component
# =============================================================================

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# Configuration
# =============================================================================

# Auto-detect domain from .env if available
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
if [[ -f "$DEPLOY_DIR/.env" ]]; then
    # shellcheck disable=SC1091
    source "$DEPLOY_DIR/.env" 2>/dev/null || true
    if [[ -n "${DOMAIN:-}" && "$DOMAIN" != "localhost" ]]; then
        STACK_URL="${STACK_URL:-https://${DOMAIN}}"
    fi
fi

STACK_URL="${STACK_URL:-http://localhost:80}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"
MEMORY_THRESHOLD="${MEMORY_THRESHOLD:-85}"
CERT_WARN_DAYS="${CERT_WARN_DAYS:-30}"

OUTPUT_FORMAT="text"
COMPONENT=""
CHECKS=()

# Results
declare -A RESULTS
OVERALL_STATUS="healthy"
WARNINGS=0
ERRORS=0

# =============================================================================
# Help
# =============================================================================

show_help() {
    show_help_header "health-check.sh" "Check health of TTS deployment"

    cat << EOF
${BOLD}Options:${NC}
    --json              Output results as JSON
    --component NAME    Check specific component only
                        (stack, postgres, redis, disk, memory, docker, ssl)
    --url URL           Override stack URL (default: $STACK_URL)
    --disk-threshold N  Disk usage threshold % (default: $DISK_THRESHOLD)
    --mem-threshold N   Memory usage threshold % (default: $MEMORY_THRESHOLD)
    --cert-warn N       SSL cert warning days (default: $CERT_WARN_DAYS)

EOF
    show_common_options

    cat << EOF
${BOLD}Exit Codes:${NC}
    0   All checks passed (healthy)
    1   Some checks have warnings (degraded)
    2   Critical failures detected

${BOLD}Examples:${NC}
    $0                              # Run all checks
    $0 --json                       # JSON output
    $0 --component stack            # Check stack only
    $0 --disk-threshold 90          # Custom threshold

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
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            --component)
                COMPONENT="$2"
                shift 2
                ;;
            --url)
                STACK_URL="$2"
                shift 2
                ;;
            --disk-threshold)
                DISK_THRESHOLD="$2"
                shift 2
                ;;
            --mem-threshold)
                MEMORY_THRESHOLD="$2"
                shift 2
                ;;
            --cert-warn)
                CERT_WARN_DAYS="$2"
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
# Check Functions
# =============================================================================

check_stack() {
    log_debug "Checking TTS Stack..."

    local url="${STACK_URL}/healthz"
    local result
    local http_code

    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null)

    if [[ "$http_code" == "200" ]]; then
        result="ok"
        RESULTS["stack"]="ok|Stack is healthy"
    elif [[ "$http_code" == "000" ]]; then
        result="error"
        RESULTS["stack"]="error|Cannot connect to $url"
        ERRORS=$((ERRORS + 1))
    else
        result="error"
        RESULTS["stack"]="error|Health check returned HTTP $http_code"
        ERRORS=$((ERRORS + 1))
    fi

    return 0
}

check_postgres() {
    log_debug "Checking PostgreSQL..."

    if ! docker_container_running "$POSTGRES_CONTAINER"; then
        RESULTS["postgres"]="error|Container not running"
        ERRORS=$((ERRORS + 1))
        return 0
    fi

    # Get credentials
    local db_user db_name
    db_user=$(docker inspect "$POSTGRES_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep POSTGRES_USER | cut -d= -f2)
    db_user="${db_user:-ttn}"
    db_name=$(docker inspect "$POSTGRES_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep POSTGRES_DB | cut -d= -f2)
    db_name="${db_name:-ttn_lorawan}"

    if docker exec "$POSTGRES_CONTAINER" pg_isready -U "$db_user" > /dev/null 2>&1; then
        # Check connection count
        local conn_count
        conn_count=$(docker exec "$POSTGRES_CONTAINER" psql -U "$db_user" -d "$db_name" -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')

        if [[ -n "$conn_count" && "$conn_count" =~ ^[0-9]+$ ]]; then
            if [[ $conn_count -gt 180 ]]; then
                RESULTS["postgres"]="warning|High connection count: $conn_count"
                WARNINGS=$((WARNINGS + 1))
            else
                RESULTS["postgres"]="ok|Connections: $conn_count"
            fi
        else
            RESULTS["postgres"]="ok|Ready"
        fi
    else
        RESULTS["postgres"]="error|Not accepting connections"
        ERRORS=$((ERRORS + 1))
    fi

    return 0
}

check_redis() {
    log_debug "Checking Redis..."

    if ! docker_container_running "$REDIS_CONTAINER"; then
        RESULTS["redis"]="error|Container not running"
        ERRORS=$((ERRORS + 1))
        return 0
    fi

    # Build Redis command with password from .env if set
    local redis_cmd="redis-cli"
    if [[ -n "${REDIS_PASSWORD:-}" ]]; then
        redis_cmd="redis-cli -a '$REDIS_PASSWORD' --no-auth-warning"
    fi

    if docker exec "$REDIS_CONTAINER" sh -c "$redis_cmd PING" 2>/dev/null | grep -q "PONG"; then
        # Check memory usage
        local used_memory
        used_memory=$(docker exec "$REDIS_CONTAINER" sh -c "$redis_cmd INFO memory" 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')

        if [[ -n "$used_memory" ]]; then
            RESULTS["redis"]="ok|Memory: $used_memory"
        else
            RESULTS["redis"]="ok|Connected"
        fi
    else
        RESULTS["redis"]="error|PING failed"
        ERRORS=$((ERRORS + 1))
    fi

    return 0
}

check_disk() {
    log_debug "Checking disk usage..."

    local usage
    usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

    if [[ $usage -ge $DISK_THRESHOLD ]]; then
        if [[ $usage -ge 95 ]]; then
            RESULTS["disk"]="error|Critical: ${usage}% used"
            ERRORS=$((ERRORS + 1))
        else
            RESULTS["disk"]="warning|High usage: ${usage}%"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        RESULTS["disk"]="ok|${usage}% used"
    fi

    return 0
}

check_memory() {
    log_debug "Checking memory usage..."

    local total used percent

    if command -v free &> /dev/null; then
        read -r total used <<< $(free | awk '/Mem:/ {print $2, $3}')
        if [[ $total -gt 0 ]]; then
            percent=$((used * 100 / total))
        else
            percent=0
        fi
    else
        percent=0
    fi

    if [[ $percent -ge $MEMORY_THRESHOLD ]]; then
        if [[ $percent -ge 95 ]]; then
            RESULTS["memory"]="error|Critical: ${percent}% used"
            ERRORS=$((ERRORS + 1))
        else
            RESULTS["memory"]="warning|High usage: ${percent}%"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        RESULTS["memory"]="ok|${percent}% used"
    fi

    return 0
}

check_docker() {
    log_debug "Checking Docker containers..."

    local containers=("$POSTGRES_CONTAINER" "$REDIS_CONTAINER" "$STACK_CONTAINER")
    local running=0
    local stopped=0
    local details=""

    for container in "${containers[@]}"; do
        if docker_container_running "$container"; then
            running=$((running + 1))
        else
            stopped=$((stopped + 1))
            details="$details $container"
        fi
    done

    if [[ $stopped -eq 0 ]]; then
        RESULTS["docker"]="ok|All $running containers running"
    elif [[ $stopped -lt ${#containers[@]} ]]; then
        RESULTS["docker"]="warning|Stopped:$details"
        WARNINGS=$((WARNINGS + 1))
    else
        RESULTS["docker"]="error|No containers running"
        ERRORS=$((ERRORS + 1))
    fi

    return 0
}

check_ssl() {
    log_debug "Checking SSL certificate..."

    # Extract domain from stack URL or use DOMAIN env
    local domain
    domain="${DOMAIN:-$(echo "$STACK_URL" | sed -E 's|https?://([^:/]+).*|\1|')}"

    if [[ "$domain" == "localhost" || "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        RESULTS["ssl"]="skip|Not applicable for $domain"
        return 0
    fi

    local expiry
    expiry=$(echo | openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null | \
             openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

    if [[ -z "$expiry" ]]; then
        RESULTS["ssl"]="warning|Could not check certificate"
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi

    local expiry_epoch
    local current_epoch
    local days_left

    expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null)
    current_epoch=$(date +%s)
    days_left=$(( (expiry_epoch - current_epoch) / 86400 ))

    if [[ $days_left -lt 0 ]]; then
        RESULTS["ssl"]="error|Certificate expired!"
        ERRORS=$((ERRORS + 1))
    elif [[ $days_left -lt $CERT_WARN_DAYS ]]; then
        RESULTS["ssl"]="warning|Expires in $days_left days"
        WARNINGS=$((WARNINGS + 1))
    else
        RESULTS["ssl"]="ok|Valid for $days_left days"
    fi

    return 0
}

# =============================================================================
# Output Functions
# =============================================================================

output_text() {
    echo ""
    echo -e "${BOLD}Olivenet TTS Health Check${NC}"
    echo "=========================="
    echo ""

    for check in "${!RESULTS[@]}"; do
        local result="${RESULTS[$check]}"
        local status="${result%%|*}"
        local message="${result#*|}"

        case $status in
            ok)
                echo -e "  ${GREEN}✓${NC} $check: $message"
                ;;
            warning)
                echo -e "  ${YELLOW}⚠${NC} $check: $message"
                ;;
            error)
                echo -e "  ${RED}✗${NC} $check: $message"
                ;;
            skip)
                echo -e "  ${CYAN}○${NC} $check: $message"
                ;;
        esac
    done

    echo ""
    echo "=========================="

    if [[ $ERRORS -gt 0 ]]; then
        echo -e "Status: ${RED}CRITICAL${NC} ($ERRORS errors, $WARNINGS warnings)"
    elif [[ $WARNINGS -gt 0 ]]; then
        echo -e "Status: ${YELLOW}DEGRADED${NC} ($WARNINGS warnings)"
    else
        echo -e "Status: ${GREEN}HEALTHY${NC}"
    fi

    echo ""
}

output_json() {
    local checks_json=""

    for check in "${!RESULTS[@]}"; do
        local result="${RESULTS[$check]}"
        local status="${result%%|*}"
        local message="${result#*|}"

        if [[ -n "$checks_json" ]]; then
            checks_json="$checks_json,"
        fi

        checks_json="$checks_json\"$check\":{\"status\":\"$status\",\"message\":\"$(json_escape "$message")\"}"
    done

    local overall="healthy"
    if [[ $ERRORS -gt 0 ]]; then
        overall="critical"
    elif [[ $WARNINGS -gt 0 ]]; then
        overall="degraded"
    fi

    cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "$overall",
  "errors": $ERRORS,
  "warnings": $WARNINGS,
  "checks": {$checks_json}
}
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Determine which checks to run
    if [[ -n "$COMPONENT" ]]; then
        CHECKS=("$COMPONENT")
    else
        CHECKS=("stack" "postgres" "redis" "disk" "memory" "docker" "ssl")
    fi

    # Validate docker is available
    require_docker

    # Run checks
    for check in "${CHECKS[@]}"; do
        case $check in
            stack)    check_stack ;;
            postgres) check_postgres ;;
            redis)    check_redis ;;
            disk)     check_disk ;;
            memory)   check_memory ;;
            docker)   check_docker ;;
            ssl)      check_ssl ;;
            *)
                log_error "Unknown component: $check"
                exit 2
                ;;
        esac
    done

    # Output results
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        output_json
    else
        output_text
    fi

    # Exit with appropriate code
    if [[ $ERRORS -gt 0 ]]; then
        exit 2
    elif [[ $WARNINGS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"
