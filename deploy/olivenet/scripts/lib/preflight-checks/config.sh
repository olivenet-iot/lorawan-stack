#!/bin/bash
# =============================================================================
# Olivenet TTS - Configuration Pre-flight Checks
# =============================================================================
# Checks configuration: .env file, YAML syntax, TLS certificates
# =============================================================================

# Required environment variables
REQUIRED_ENV_VARS=(
    "DOMAIN"
    "ADMIN_EMAIL"
    "POSTGRES_PASSWORD"
    "REDIS_PASSWORD"
    "TTN_LW_CONSOLE_OAUTH_CLIENT_SECRET"
)

# Placeholder patterns to detect
PLACEHOLDER_PATTERNS=(
    "CHANGE_ME"
    "GENERATE_ME"
    "YOUR_"
    "REPLACE_"
    "<your"
    "example.com"
)

# =============================================================================
# Check Functions
# =============================================================================

check_env_file() {
    local env_file="${DEPLOY_DIR:-.}/.env"

    if [[ ! -f "$env_file" ]]; then
        # Check if .env.example exists
        if [[ -f "${env_file}.example" ]]; then
            RESULTS["env_file"]="error|.env not found (copy from .env.example)"
        else
            RESULTS["env_file"]="error|.env not found"
        fi
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    if [[ ! -r "$env_file" ]]; then
        RESULTS["env_file"]="error|.env not readable"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    RESULTS["env_file"]="ok|Found"
    return 0
}

check_required_env_vars() {
    local env_file="${DEPLOY_DIR:-.}/.env"
    local missing=()

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    # Source env file to check variables
    set -a
    # shellcheck source=/dev/null
    source "$env_file" 2>/dev/null
    set +a

    for var in "${REQUIRED_ENV_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        RESULTS["env_vars"]="error|Missing: ${missing[*]}"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    RESULTS["env_vars"]="ok|All required variables set"
    return 0
}

check_no_placeholders() {
    local env_file="${DEPLOY_DIR:-.}/.env"
    local found=()

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    for pattern in "${PLACEHOLDER_PATTERNS[@]}"; do
        if grep -qi "$pattern" "$env_file" 2>/dev/null; then
            local matches
            matches=$(grep -i "$pattern" "$env_file" | head -1 | cut -d= -f1)
            found+=("$matches")
        fi
    done

    if [[ ${#found[@]} -gt 0 ]]; then
        RESULTS["placeholders"]="error|Placeholder values found: ${found[*]}"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    RESULTS["placeholders"]="ok|No placeholder values"
    return 0
}

check_yaml_syntax() {
    local config_file="${DEPLOY_DIR:-.}/docker-compose.yml"

    if [[ ! -f "$config_file" ]]; then
        RESULTS["yaml_syntax"]="error|docker-compose.yml not found"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    # Check if docker compose can parse it
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        if docker compose -f "$config_file" config --quiet 2>/dev/null; then
            RESULTS["yaml_syntax"]="ok|docker-compose.yml valid"
            return 0
        else
            RESULTS["yaml_syntax"]="error|docker-compose.yml syntax error"
            ERRORS=$((ERRORS + 1))
            return 1
        fi
    fi

    # Fallback: Check if Python can parse YAML
    if command -v python3 &>/dev/null; then
        if python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
            RESULTS["yaml_syntax"]="ok|docker-compose.yml valid"
            return 0
        else
            RESULTS["yaml_syntax"]="error|docker-compose.yml syntax error"
            ERRORS=$((ERRORS + 1))
            return 1
        fi
    fi

    RESULTS["yaml_syntax"]="ok|Cannot validate (no parser)"
}

check_tls_certificates() {
    local env_file="${DEPLOY_DIR:-.}/.env"

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    # Source env to get TLS settings
    set -a
    # shellcheck source=/dev/null
    source "$env_file" 2>/dev/null
    set +a

    # Check if TLS is enabled
    if [[ "${TLS_ACME:-false}" == "true" ]]; then
        RESULTS["tls_certs"]="ok|Using ACME (Let's Encrypt)"
        return 0
    fi

    # Check for certificate files
    local cert_file="${TLS_CERTIFICATE:-}"
    local key_file="${TLS_KEY:-}"

    if [[ -z "$cert_file" && -z "$key_file" ]]; then
        RESULTS["tls_certs"]="warning|TLS not configured (HTTP only)"
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi

    if [[ ! -f "$cert_file" ]]; then
        RESULTS["tls_certs"]="error|Certificate file not found: $cert_file"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    if [[ ! -f "$key_file" ]]; then
        RESULTS["tls_certs"]="error|Key file not found: $key_file"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    RESULTS["tls_certs"]="ok|Certificates found"
    return 0
}

check_cert_expiry() {
    local env_file="${DEPLOY_DIR:-.}/.env"

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    # Source env
    set -a
    # shellcheck source=/dev/null
    source "$env_file" 2>/dev/null
    set +a

    # Skip if using ACME
    if [[ "${TLS_ACME:-false}" == "true" ]]; then
        RESULTS["cert_expiry"]="ok|ACME auto-renewal"
        return 0
    fi

    local cert_file="${TLS_CERTIFICATE:-}"

    if [[ -z "$cert_file" || ! -f "$cert_file" ]]; then
        return 0
    fi

    # Check certificate expiry
    if command -v openssl &>/dev/null; then
        local expiry
        local expiry_epoch
        local now_epoch
        local days_left

        expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)

        if [[ -n "$expiry" ]]; then
            expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
            now_epoch=$(date +%s)
            days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

            if [[ $days_left -lt 0 ]]; then
                RESULTS["cert_expiry"]="error|Certificate expired!"
                ERRORS=$((ERRORS + 1))
            elif [[ $days_left -lt 7 ]]; then
                RESULTS["cert_expiry"]="error|Certificate expires in $days_left days!"
                ERRORS=$((ERRORS + 1))
            elif [[ $days_left -lt 30 ]]; then
                RESULTS["cert_expiry"]="warning|Certificate expires in $days_left days"
                WARNINGS=$((WARNINGS + 1))
            else
                RESULTS["cert_expiry"]="ok|Valid for $days_left days"
            fi
            return 0
        fi
    fi

    RESULTS["cert_expiry"]="ok|Cannot check expiry"
}

check_stack_config() {
    local config_file="${DEPLOY_DIR:-.}/config/ttn-lw-stack.yml"

    if [[ ! -f "$config_file" ]]; then
        RESULTS["stack_config"]="warning|ttn-lw-stack.yml not found"
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi

    # Basic syntax check
    if command -v python3 &>/dev/null; then
        if python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
            RESULTS["stack_config"]="ok|ttn-lw-stack.yml valid"
        else
            RESULTS["stack_config"]="error|ttn-lw-stack.yml syntax error"
            ERRORS=$((ERRORS + 1))
        fi
    else
        RESULTS["stack_config"]="ok|Cannot validate"
    fi
}

# =============================================================================
# Main Function
# =============================================================================

run_config_checks() {
    log_debug "Running configuration checks..."

    check_env_file || true
    if [[ "${RESULTS[env_file]:-}" == ok* ]]; then
        check_required_env_vars || true
        check_no_placeholders || true
    fi
    check_yaml_syntax || true
    check_stack_config || true
    check_tls_certificates || true
    check_cert_expiry || true
}
