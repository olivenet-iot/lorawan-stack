#!/bin/bash
# =============================================================================
# Olivenet TTS - Pre-flight Check Script
# =============================================================================
# Comprehensive deployment readiness check for The Things Stack
#
# Checks:
#   - System: OS, CPU, RAM, disk, swap
#   - Docker: installation, daemon, compose
#   - Network: ports, DNS, connectivity
#   - Config: .env, YAML syntax, TLS
#   - Security: passwords, secrets, permissions
#
# Exit codes:
#   0 = All checks passed, ready to deploy
#   1 = Warnings present, can proceed with caution
#   2 = Critical errors, must fix before deployment
#
# Usage:
#   ./preflight-check.sh              # All checks
#   ./preflight-check.sh --quick      # Only critical checks
#   ./preflight-check.sh --category system  # Specific category
#   ./preflight-check.sh --json       # JSON output
#   ./preflight-check.sh --fix        # Attempt to fix issues
# =============================================================================

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# Configuration
# =============================================================================

# Categories of checks
CHECK_CATEGORIES=("system" "docker" "network" "config" "security")

# Default to deploy directory
DEPLOY_DIR="${DEPLOY_DIR:-$(dirname "$SCRIPT_DIR")}"

# Output format
OUTPUT_FORMAT="text"
QUICK_MODE=false
FIX_MODE=false
CATEGORY=""

# Results
declare -A RESULTS
WARNINGS=0
ERRORS=0
PASSED=0

# =============================================================================
# Help
# =============================================================================

show_help() {
    show_help_header "preflight-check.sh" "Pre-flight deployment readiness check"

    cat << EOF
${BOLD}Options:${NC}
    --json              Output results as JSON
    --quick             Only run critical checks
    --category NAME     Check specific category only
                        (system, docker, network, config, security)
    --deploy-dir DIR    Override deployment directory
    --fix               Attempt to fix simple issues

EOF
    show_common_options

    cat << EOF
${BOLD}Exit Codes:${NC}
    0   All checks passed (ready to deploy)
    1   Warnings present (proceed with caution)
    2   Critical errors (must fix before deployment)

${BOLD}Examples:${NC}
    $0                              # Run all checks
    $0 --json                       # JSON output
    $0 --category docker            # Check Docker only
    $0 --quick                      # Critical checks only
    $0 --fix                        # Attempt to fix issues

${BOLD}Categories:${NC}
    system      OS, CPU, RAM, disk space, swap
    docker      Docker installation, daemon, compose
    network     Port availability, DNS, connectivity
    config      .env file, YAML syntax, TLS certificates
    security    Passwords, secrets, file permissions

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
                # Reinitialize colors
                RED=""
                GREEN=""
                YELLOW=""
                BLUE=""
                CYAN=""
                NC=""
                BOLD=""
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
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            --quick)
                QUICK_MODE=true
                shift
                ;;
            --fix)
                FIX_MODE=true
                shift
                ;;
            --category)
                CATEGORY="$2"
                shift 2
                ;;
            --deploy-dir)
                DEPLOY_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 2
                ;;
        esac
    done

    # Validate category
    if [[ -n "$CATEGORY" ]]; then
        local valid=false
        for cat in "${CHECK_CATEGORIES[@]}"; do
            if [[ "$cat" == "$CATEGORY" ]]; then
                valid=true
                break
            fi
        done
        if [[ "$valid" == "false" ]]; then
            log_error "Invalid category: $CATEGORY"
            log_error "Valid categories: ${CHECK_CATEGORIES[*]}"
            exit 2
        fi
    fi
}

# =============================================================================
# Source Check Modules
# =============================================================================

source_check_modules() {
    local checks_dir="${SCRIPT_DIR}/lib/preflight-checks"

    for category in "${CHECK_CATEGORIES[@]}"; do
        local module="${checks_dir}/${category}.sh"
        if [[ -f "$module" ]]; then
            # shellcheck source=/dev/null
            source "$module"
        else
            log_warn "Check module not found: $module"
        fi
    done
}

# =============================================================================
# Run Checks
# =============================================================================

run_checks() {
    local categories=()

    if [[ -n "$CATEGORY" ]]; then
        categories=("$CATEGORY")
    elif [[ "$QUICK_MODE" == "true" ]]; then
        categories=("docker" "network" "config")
    else
        categories=("${CHECK_CATEGORIES[@]}")
    fi

    for category in "${categories[@]}"; do
        log_debug "Running $category checks..."

        case "$category" in
            system)
                run_system_checks
                ;;
            docker)
                run_docker_checks
                ;;
            network)
                run_network_checks
                ;;
            config)
                run_config_checks
                ;;
            security)
                run_security_checks
                ;;
        esac
    done
}

# =============================================================================
# Output Functions
# =============================================================================

output_text() {
    local box_width=68

    echo ""
    echo "╔$(printf '═%.0s' $(seq 1 $box_width))╗"
    echo "║$(printf ' %.0s' $(seq 1 17))${BOLD}TTS Pre-flight Check - Olivenet${NC}$(printf ' %.0s' $(seq 1 18))║"
    echo "╠$(printf '═%.0s' $(seq 1 $box_width))╣"

    # Group results by category
    local current_category=""

    for key in $(echo "${!RESULTS[@]}" | tr ' ' '\n' | sort); do
        local result="${RESULTS[$key]}"
        local status="${result%%|*}"
        local message="${result#*|}"

        # Determine category from key
        local category=""
        case "$key" in
            os_*|cpu_*|ram|disk_*|swap|time_*)
                category="System Checks"
                ;;
            docker_*|port_*)
                category="Docker Checks"
                ;;
            dns|internet|ipv4_*|firewall)
                category="Network Checks"
                ;;
            env_*|yaml_*|tls_*|cert_*|stack_*|placeholders)
                category="Config Checks"
                ;;
            default_*|secret_*|file_*|https|admin_*|sensitive_*)
                category="Security Checks"
                ;;
            *)
                category="Other"
                ;;
        esac

        # Print category header if changed
        if [[ "$category" != "$current_category" ]]; then
            if [[ -n "$current_category" ]]; then
                echo "╟$(printf '─%.0s' $(seq 1 $box_width))╢"
            fi
            echo "║ ${BOLD}$category${NC}$(printf ' %.0s' $(seq 1 $((box_width - ${#category} - 1))))║"
            echo "╟$(printf '─%.0s' $(seq 1 $box_width))╢"
            current_category="$category"
        fi

        # Format status
        local status_icon
        case "$status" in
            ok)
                status_icon="${GREEN}✓${NC}"
                PASSED=$((PASSED + 1))
                ;;
            warning)
                status_icon="${YELLOW}⚠${NC}"
                ;;
            error)
                status_icon="${RED}✗${NC}"
                ;;
            skip)
                status_icon="${CYAN}○${NC}"
                PASSED=$((PASSED + 1))
                ;;
        esac

        # Format key for display
        local display_key
        display_key=$(echo "$key" | sed 's/_/ /g' | sed 's/\b\(.\)/\u\1/g')

        # Truncate message if too long
        local max_msg_len=$((box_width - 30))
        if [[ ${#message} -gt $max_msg_len ]]; then
            message="${message:0:$((max_msg_len-3))}..."
        fi

        # Print result line
        printf "║ %s %-20s │ %-*s ║\n" "$status_icon" "$display_key" $((box_width - 27)) "$message"
    done

    echo "╟$(printf '─%.0s' $(seq 1 $box_width))╢"
    echo "║ ${BOLD}Summary${NC}$(printf ' %.0s' $(seq 1 $((box_width - 8))))║"
    echo "╟$(printf '─%.0s' $(seq 1 $box_width))╢"

    printf "║ ✓ Passed: %-5d │ ⚠ Warnings: %-5d │ ✗ Failed: %-5d    ║\n" "$PASSED" "$WARNINGS" "$ERRORS"

    echo "╠$(printf '═%.0s' $(seq 1 $box_width))╣"

    # Final status
    local final_status
    local status_color
    if [[ $ERRORS -gt 0 ]]; then
        final_status="BLOCKED - Fix critical issues before deployment"
        status_color="$RED"
    elif [[ $WARNINGS -gt 0 ]]; then
        final_status="READY (with warnings) - Review before deployment"
        status_color="$YELLOW"
    else
        final_status="READY - All checks passed!"
        status_color="$GREEN"
    fi

    local status_len=${#final_status}
    local padding=$(( (box_width - status_len) / 2 ))
    printf "║%*s${status_color}${BOLD}%s${NC}%*s║\n" $padding "" "$final_status" $((box_width - padding - status_len)) ""

    echo "╚$(printf '═%.0s' $(seq 1 $box_width))╝"
    echo ""
}

output_json() {
    local checks_json=""

    for key in "${!RESULTS[@]}"; do
        local result="${RESULTS[$key]}"
        local status="${result%%|*}"
        local message="${result#*|}"

        if [[ -n "$checks_json" ]]; then
            checks_json="$checks_json,"
        fi

        checks_json="$checks_json\"$key\":{\"status\":\"$status\",\"message\":\"$(json_escape "$message")\"}"
    done

    local overall="ready"
    if [[ $ERRORS -gt 0 ]]; then
        overall="blocked"
    elif [[ $WARNINGS -gt 0 ]]; then
        overall="warning"
    fi

    cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "$overall",
  "passed": $PASSED,
  "warnings": $WARNINGS,
  "errors": $ERRORS,
  "checks": {$checks_json}
}
EOF
}

# =============================================================================
# Fix Functions
# =============================================================================

attempt_fixes() {
    if [[ "$FIX_MODE" != "true" ]]; then
        return
    fi

    log_info "Attempting to fix issues..."

    # Fix: Copy .env from .env.example
    if [[ "${RESULTS[env_file]}" == error* ]]; then
        if [[ -f "${DEPLOY_DIR}/.env.example" ]]; then
            if confirm "Copy .env.example to .env?"; then
                cp "${DEPLOY_DIR}/.env.example" "${DEPLOY_DIR}/.env"
                log_success "Created .env from .env.example"
            fi
        fi
    fi

    # Fix: File permissions
    if [[ "${RESULTS[file_permissions]}" == warning* ]]; then
        if confirm "Set .env permissions to 600?"; then
            chmod 600 "${DEPLOY_DIR}/.env"
            log_success "Set .env permissions to 600"
        fi
    fi

    # Suggest: Generate secrets
    if [[ "${RESULTS[secret_strength]}" == warning* ]]; then
        log_info "Generate secrets with:"
        log_info "  openssl rand -hex 32  # For 64-char hex string"
        log_info "  openssl rand -base64 24  # For 32-char base64 string"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Export DEPLOY_DIR for check modules
    export DEPLOY_DIR

    # Source check modules
    source_check_modules

    # Run checks
    run_checks

    # Attempt fixes if requested
    attempt_fixes

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
