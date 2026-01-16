#!/bin/bash
# =============================================================================
# Olivenet TTS - Installation Validator
# =============================================================================
# Runs all validation checks and generates a report
#
# Usage:
#   ./validate.sh              # Run all checks
#   ./validate.sh --quick      # Quick checks only
#   ./validate.sh --json       # JSON output
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0
SKIPPED=0

# Options
QUICK_MODE=false
JSON_OUTPUT=false

# Container names
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-olivenet-postgres}"
REDIS_CONTAINER="${REDIS_CONTAINER:-olivenet-redis}"
STACK_CONTAINER="${STACK_CONTAINER:-olivenet-stack}"

# Load config
if [[ -f "$DEPLOY_DIR/.env" ]]; then
    # shellcheck disable=SC1091
    source "$DEPLOY_DIR/.env" 2>/dev/null || true
fi
DOMAIN="${DOMAIN:-localhost}"

# =============================================================================
# Helper Functions
# =============================================================================

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Olivenet TTS Installation Validator

Options:
    -q, --quick     Run quick checks only (skip simulator tests)
    -j, --json      Output results as JSON
    -h, --help      Show this help message

Examples:
    $(basename "$0")              # Run all checks
    $(basename "$0") --quick      # Quick mode
    $(basename "$0") --json       # JSON output for automation

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quick)
                QUICK_MODE=true
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

check() {
    local name="$1"
    local cmd="$2"
    local expected="${3:-}"

    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -n "  Checking $name... "
    fi

    local result
    if result=$(eval "$cmd" 2>/dev/null); then
        if [[ -z "$expected" ]] || echo "$result" | grep -q "$expected"; then
            if [[ "$JSON_OUTPUT" == "false" ]]; then
                echo -e "${GREEN}OK${NC}"
            fi
            PASSED=$((PASSED + 1))
            return 0
        fi
    fi

    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "${RED}FAILED${NC}"
    fi
    FAILED=$((FAILED + 1))
    return 1
}

warn() {
    local name="$1"
    local msg="$2"
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "  ${YELLOW}!${NC} $name: $msg"
    fi
    WARNINGS=$((WARNINGS + 1))
}

skip() {
    local name="$1"
    local msg="$2"
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "  ${CYAN}-${NC} $name: $msg"
    fi
    SKIPPED=$((SKIPPED + 1))
}

section() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${BLUE}$1${NC}"
    fi
}

# =============================================================================
# Check Functions
# =============================================================================

check_containers() {
    section "[1/7] Container Status"

    check "PostgreSQL container" \
        "docker inspect $POSTGRES_CONTAINER --format '{{.State.Running}}'" \
        "true"

    check "Redis container" \
        "docker inspect $REDIS_CONTAINER --format '{{.State.Running}}'" \
        "true"

    check "Stack container" \
        "docker inspect $STACK_CONTAINER --format '{{.State.Running}}'" \
        "true"

    # Check health status
    local stack_health
    stack_health=$(docker inspect "$STACK_CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
    if [[ "$stack_health" == "healthy" ]]; then
        check "Stack health" "echo healthy" "healthy"
    elif [[ "$stack_health" == "none" ]]; then
        skip "Stack health" "No health check configured"
    else
        warn "Stack health" "Status: $stack_health"
    fi
}

check_databases() {
    section "[2/7] Database Connectivity"

    check "PostgreSQL ready" \
        "docker exec $POSTGRES_CONTAINER pg_isready -U ttn" \
        "accepting"

    # Build Redis command with password if set
    local redis_check_cmd
    if [[ -n "${REDIS_PASSWORD:-}" ]]; then
        redis_check_cmd="docker exec -e REDISCLI_AUTH=\"\$REDIS_PASSWORD\" $REDIS_CONTAINER redis-cli --no-auth-warning ping"
    else
        redis_check_cmd="docker exec $REDIS_CONTAINER redis-cli ping"
    fi

    check "Redis ping" \
        "$redis_check_cmd" \
        "PONG"
}

check_api() {
    section "[3/7] API Health"

    local health_url
    if [[ "$DOMAIN" == "localhost" ]]; then
        health_url="http://localhost:80/healthz"
    else
        health_url="https://${DOMAIN}/healthz"
    fi

    check "Health endpoint" \
        "curl -sk --connect-timeout 5 '$health_url'" \
        "status"
}

check_ports() {
    section "[4/7] Port Availability"

    # Check if container has netstat
    if docker exec "$STACK_CONTAINER" which netstat &>/dev/null; then
        check "UDP 1700 (Gateway)" \
            "docker exec $STACK_CONTAINER netstat -ulnp 2>/dev/null | grep ':1700'" \
            "1700"

        check "TCP 1883 (MQTT)" \
            "docker exec $STACK_CONTAINER netstat -tlnp 2>/dev/null | grep ':1883'" \
            "1883"

        check "TCP 8883 (MQTTS)" \
            "docker exec $STACK_CONTAINER netstat -tlnp 2>/dev/null | grep ':8883'" \
            "8883"

        check "TCP 8885 (HTTPS)" \
            "docker exec $STACK_CONTAINER netstat -tlnp 2>/dev/null | grep ':8885'" \
            "8885"
    else
        # Alternative: check from host
        check "UDP 1700 (Gateway)" \
            "docker port $STACK_CONTAINER 1700/udp" \
            ""

        skip "Internal port check" "netstat not available in container"
    fi
}

check_tls() {
    section "[5/7] TLS Certificate"

    if [[ "$DOMAIN" == "localhost" || "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        skip "TLS certificate" "Not applicable for $DOMAIN"
        return 0
    fi

    local cert_info
    cert_info=$(echo | openssl s_client -connect "${DOMAIN}:443" -servername "$DOMAIN" 2>/dev/null)

    if echo "$cert_info" | openssl x509 -noout -checkend 0 2>/dev/null; then
        check "Certificate valid" "echo valid" "valid"

        # Check expiry
        local expiry
        expiry=$(echo "$cert_info" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry" ]]; then
            local expiry_epoch current_epoch days_left
            expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null)
            current_epoch=$(date +%s)
            days_left=$(( (expiry_epoch - current_epoch) / 86400 ))

            if [[ $days_left -lt 30 ]]; then
                warn "Certificate expiry" "Expires in $days_left days"
            else
                if [[ "$JSON_OUTPUT" == "false" ]]; then
                    echo -e "  ${BLUE}i${NC} Certificate expires: $expiry ($days_left days)"
                fi
            fi
        fi
    else
        warn "TLS certificate" "Certificate invalid or expired"
    fi
}

check_database_state() {
    section "[6/7] Database State"

    # Check OAuth client
    local oauth_check
    oauth_check=$(docker exec "$POSTGRES_CONTAINER" psql -U ttn -d ttn_lorawan -t -c \
        "SELECT grants FROM clients WHERE client_id='console';" 2>/dev/null | tr -d ' \n')

    if [[ "$oauth_check" == "{0,2}" ]]; then
        check "OAuth client (console)" "echo ok" "ok"
    elif [[ -n "$oauth_check" ]]; then
        warn "OAuth client" "grants=$oauth_check (expected {0,2})"
    else
        warn "OAuth client" "Console client not found"
    fi

    # Check table count
    local table_count
    table_count=$(docker exec "$POSTGRES_CONTAINER" psql -U ttn -d ttn_lorawan -t -c \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null | tr -d ' \n')

    if [[ -n "$table_count" && "$table_count" -gt 10 ]]; then
        check "Database tables" "echo $table_count" ""
    else
        warn "Database tables" "Only $table_count tables found"
    fi
}

check_gateway_connectivity() {
    section "[7/7] Gateway Connectivity"

    if [[ "$QUICK_MODE" == "true" ]]; then
        skip "Gateway test" "Skipped in quick mode"
        return 0
    fi

    # Check if simulator is available
    if [[ ! -f "$DEPLOY_DIR/simulator/gateway_simulator.py" ]]; then
        skip "Gateway test" "Simulator not found"
        return 0
    fi

    if [[ ! -d "$DEPLOY_DIR/simulator/venv" ]]; then
        skip "Gateway test" "Simulator venv not installed. Run ./scripts/setup-tools.sh"
        return 0
    fi

    # Run gateway test
    local gw_result
    cd "$DEPLOY_DIR/simulator"

    # shellcheck disable=SC1091
    source venv/bin/activate 2>/dev/null || true

    # Check if pycryptodome works
    if ! python3 -c "from Crypto.Cipher import AES" 2>/dev/null; then
        warn "Gateway test" "pycryptodome not working. Run: ./scripts/setup-tools.sh --force"
        deactivate 2>/dev/null || true
        cd "$DEPLOY_DIR"
        return 0
    fi

    if gw_result=$(timeout 10 python3 gateway_simulator.py \
        --server "$DOMAIN" \
        --port 1700 \
        --eui AA555A0000000001 \
        --test-only 2>&1); then
        if echo "$gw_result" | grep -q "PULL_ACK"; then
            check "Gateway PULL_ACK" "echo received" "received"
        else
            warn "Gateway test" "No PULL_ACK received"
        fi
    else
        warn "Gateway test" "Connection failed"
    fi

    deactivate 2>/dev/null || true
    cd "$DEPLOY_DIR"
}

# =============================================================================
# Output Functions
# =============================================================================

output_summary() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json
    else
        output_text
    fi
}

output_text() {
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "  ${GREEN}Passed:${NC} $PASSED    ${YELLOW}Warnings:${NC} $WARNINGS    ${RED}Failed:${NC} $FAILED    ${CYAN}Skipped:${NC} $SKIPPED"
    echo -e "${BLUE}================================================================${NC}"

    local total=$((PASSED + FAILED))
    if [[ $FAILED -eq 0 && $WARNINGS -eq 0 ]]; then
        echo -e "\n${GREEN}${BOLD}All checks passed!${NC}"
        echo -e "\nConsole URL: https://${DOMAIN}/console"
    elif [[ $FAILED -eq 0 ]]; then
        echo -e "\n${YELLOW}${BOLD}Checks passed with warnings.${NC}"
        echo -e "\nConsole URL: https://${DOMAIN}/console"
    else
        echo -e "\n${RED}${BOLD}Some checks failed. Review the output above.${NC}"
    fi
    echo ""
}

output_json() {
    local status="healthy"
    if [[ $FAILED -gt 0 ]]; then
        status="critical"
    elif [[ $WARNINGS -gt 0 ]]; then
        status="degraded"
    fi

    cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "domain": "$DOMAIN",
  "status": "$status",
  "passed": $PASSED,
  "failed": $FAILED,
  "warnings": $WARNINGS,
  "skipped": $SKIPPED
}
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo ""
        echo -e "${BLUE}${BOLD}================================================================${NC}"
        echo -e "${BLUE}${BOLD}           TTS Installation Validator                          ${NC}"
        echo -e "${BLUE}${BOLD}================================================================${NC}"
        echo ""
        echo -e "Domain: ${CYAN}${DOMAIN}${NC}"
        if [[ "$QUICK_MODE" == "true" ]]; then
            echo -e "Mode: ${YELLOW}Quick${NC}"
        fi
    fi

    # Run all checks
    check_containers
    check_databases
    check_api
    check_ports
    check_tls
    check_database_state
    check_gateway_connectivity

    # Output summary
    output_summary

    # Exit with appropriate code
    if [[ $FAILED -gt 0 ]]; then
        exit 2
    elif [[ $WARNINGS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"
