#!/bin/bash
# =============================================================================
# Olivenet TTS - Security Pre-flight Checks
# =============================================================================
# Checks security: passwords, secrets, file permissions
# =============================================================================

# Minimum secret length
MIN_SECRET_LENGTH=32

# Default/weak passwords to detect
WEAK_PASSWORDS=(
    "password"
    "admin"
    "admin123"
    "123456"
    "changeme"
    "secret"
    "default"
    "ttn"
    "lorawan"
)

# Secrets that should be strong
SECRET_VARS=(
    "POSTGRES_PASSWORD"
    "REDIS_PASSWORD"
    "TTN_LW_CONSOLE_OAUTH_CLIENT_SECRET"
    "TTN_LW_IS_DATABASE_URI"
    "TTN_LW_COOKIE_HASH_KEY"
    "TTN_LW_COOKIE_BLOCK_KEY"
)

# =============================================================================
# Check Functions
# =============================================================================

check_no_default_passwords() {
    local env_file="${DEPLOY_DIR:-.}/.env"
    local weak_found=()

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    for password in "${WEAK_PASSWORDS[@]}"; do
        if grep -qi "PASSWORD.*=.*${password}" "$env_file" 2>/dev/null || \
           grep -qi "SECRET.*=.*${password}" "$env_file" 2>/dev/null; then
            weak_found+=("$password")
        fi
    done

    if [[ ${#weak_found[@]} -gt 0 ]]; then
        RESULTS["default_passwords"]="error|Weak passwords detected: ${weak_found[*]}"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    RESULTS["default_passwords"]="ok|No default passwords"
    return 0
}

check_secret_strength() {
    local env_file="${DEPLOY_DIR:-.}/.env"
    local weak_secrets=()

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    # Source env file
    set -a
    # shellcheck source=/dev/null
    source "$env_file" 2>/dev/null
    set +a

    for var in "${SECRET_VARS[@]}"; do
        local value="${!var:-}"

        # Skip if not set
        if [[ -z "$value" ]]; then
            continue
        fi

        # Extract password from URI if needed
        if [[ "$var" == *"URI"* ]]; then
            value=$(echo "$value" | grep -oP '://[^:]+:\K[^@]+' || echo "$value")
        fi

        # Check length
        if [[ ${#value} -lt $MIN_SECRET_LENGTH ]]; then
            # Some secrets like Redis password can be shorter
            if [[ "$var" == "REDIS_PASSWORD" && ${#value} -ge 16 ]]; then
                continue
            elif [[ "$var" == "POSTGRES_PASSWORD" && ${#value} -ge 16 ]]; then
                continue
            fi
            weak_secrets+=("$var")
        fi
    done

    if [[ ${#weak_secrets[@]} -gt 0 ]]; then
        RESULTS["secret_strength"]="warning|Short secrets: ${weak_secrets[*]} (${MIN_SECRET_LENGTH}+ chars recommended)"
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi

    RESULTS["secret_strength"]="ok|All secrets have adequate length"
    return 0
}

check_file_permissions() {
    local env_file="${DEPLOY_DIR:-.}/.env"

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    local perms
    perms=$(stat -c "%a" "$env_file" 2>/dev/null)

    if [[ -z "$perms" ]]; then
        RESULTS["file_permissions"]="ok|Cannot check"
        return 0
    fi

    # Check if file is world-readable
    if [[ ${perms: -1} -ge 4 ]]; then
        RESULTS["file_permissions"]="warning|.env is world-readable ($perms) - consider chmod 600"
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi

    # Check if file is group-readable
    if [[ ${perms: -2:1} -ge 4 ]]; then
        RESULTS["file_permissions"]="warning|.env is group-readable ($perms) - consider chmod 600"
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi

    RESULTS["file_permissions"]="ok|.env permissions: $perms"
    return 0
}

check_https_enforced() {
    local env_file="${DEPLOY_DIR:-.}/.env"

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    # Source env file
    set -a
    # shellcheck source=/dev/null
    source "$env_file" 2>/dev/null
    set +a

    # Check if TLS is configured
    if [[ "${TLS_ACME:-false}" == "true" ]] || \
       [[ -n "${TLS_CERTIFICATE:-}" ]]; then
        RESULTS["https"]="ok|TLS configured"
        return 0
    fi

    # Check domain - if not localhost, HTTPS should be used
    local domain="${DOMAIN:-localhost}"
    if [[ "$domain" != "localhost" && ! "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        RESULTS["https"]="warning|HTTPS not configured for $domain (recommended for production)"
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi

    RESULTS["https"]="ok|Local deployment (HTTP acceptable)"
    return 0
}

check_admin_api_key() {
    local env_file="${DEPLOY_DIR:-.}/.env"

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    # Source env file
    set -a
    # shellcheck source=/dev/null
    source "$env_file" 2>/dev/null
    set +a

    # Check if admin user is configured with default password
    if [[ -n "${ADMIN_PASSWORD:-}" ]]; then
        for weak in "${WEAK_PASSWORDS[@]}"; do
            if [[ "${ADMIN_PASSWORD,,}" == "${weak,,}" ]]; then
                RESULTS["admin_password"]="error|Default admin password detected"
                ERRORS=$((ERRORS + 1))
                return 1
            fi
        done

        if [[ ${#ADMIN_PASSWORD} -lt 12 ]]; then
            RESULTS["admin_password"]="warning|Admin password is short (12+ chars recommended)"
            WARNINGS=$((WARNINGS + 1))
            return 0
        fi

        RESULTS["admin_password"]="ok|Admin password set"
    else
        RESULTS["admin_password"]="ok|Will be generated"
    fi

    return 0
}

check_sensitive_files() {
    local deploy_dir="${DEPLOY_DIR:-.}"
    local issues=()

    # Check for exposed secrets
    local sensitive_patterns=(
        "*.pem"
        "*.key"
        "*secret*"
        "*password*"
        "*.p12"
        "*.pfx"
    )

    # Check if any sensitive files are in git
    if [[ -d "${deploy_dir}/.git" ]] && command -v git &>/dev/null; then
        for pattern in "${sensitive_patterns[@]}"; do
            if git -C "$deploy_dir" ls-files "$pattern" 2>/dev/null | grep -q .; then
                issues+=("$pattern in git")
            fi
        done
    fi

    if [[ ${#issues[@]} -gt 0 ]]; then
        RESULTS["sensitive_files"]="warning|Sensitive files may be tracked: ${issues[*]}"
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi

    RESULTS["sensitive_files"]="ok|No sensitive files exposed"
    return 0
}

# =============================================================================
# Main Function
# =============================================================================

run_security_checks() {
    log_debug "Running security checks..."

    check_no_default_passwords || true
    check_secret_strength || true
    check_file_permissions || true
    check_https_enforced || true
    check_admin_api_key || true
    check_sensitive_files || true
}
