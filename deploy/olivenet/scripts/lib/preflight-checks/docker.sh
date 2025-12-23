#!/bin/bash
# =============================================================================
# Olivenet TTS - Docker Pre-flight Checks
# =============================================================================
# Checks Docker requirements: installation, version, daemon, compose
# =============================================================================

# Minimum versions
MIN_DOCKER_VERSION="20.10"
MIN_COMPOSE_VERSION="2.0"

# =============================================================================
# Check Functions
# =============================================================================

check_docker_installed() {
    if ! command -v docker &>/dev/null; then
        RESULTS["docker_installed"]="error|Docker not installed"
        ((ERRORS++))
        return 1
    fi

    local version
    version=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)

    if [[ -z "$version" ]]; then
        RESULTS["docker_installed"]="error|Cannot determine Docker version"
        ((ERRORS++))
        return 1
    fi

    # Compare versions
    if version_compare "$version" "$MIN_DOCKER_VERSION"; then
        RESULTS["docker_installed"]="ok|Docker $version"
        return 0
    else
        RESULTS["docker_installed"]="error|Docker $version (>= $MIN_DOCKER_VERSION required)"
        ((ERRORS++))
        return 1
    fi
}

check_docker_daemon() {
    if ! docker info &>/dev/null; then
        # Check if it's a permission issue
        if groups | grep -q docker; then
            RESULTS["docker_daemon"]="error|Docker daemon not running"
        else
            RESULTS["docker_daemon"]="error|Docker daemon not accessible (add user to docker group)"
        fi
        ((ERRORS++))
        return 1
    fi

    RESULTS["docker_daemon"]="ok|Running"
    return 0
}

check_docker_compose() {
    local version=""

    # Check docker compose (v2 plugin)
    if docker compose version &>/dev/null; then
        version=$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
    # Check docker-compose (standalone v1)
    elif command -v docker-compose &>/dev/null; then
        version=$(docker-compose --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
    fi

    if [[ -z "$version" ]]; then
        RESULTS["docker_compose"]="error|Docker Compose not installed"
        ((ERRORS++))
        return 1
    fi

    if version_compare "$version" "$MIN_COMPOSE_VERSION"; then
        RESULTS["docker_compose"]="ok|Compose $version"
        return 0
    else
        RESULTS["docker_compose"]="warning|Compose $version (>= $MIN_COMPOSE_VERSION recommended)"
        ((WARNINGS++))
        return 0
    fi
}

check_docker_socket() {
    local socket="/var/run/docker.sock"

    if [[ ! -S "$socket" ]]; then
        RESULTS["docker_socket"]="error|Docker socket not found"
        ((ERRORS++))
        return 1
    fi

    if [[ ! -r "$socket" ]]; then
        RESULTS["docker_socket"]="error|Docker socket not readable (check permissions)"
        ((ERRORS++))
        return 1
    fi

    RESULTS["docker_socket"]="ok|Socket accessible"
    return 0
}

check_docker_disk() {
    # Check Docker disk usage
    local docker_root
    local usage_percent

    docker_root=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $4}')

    if [[ -z "$docker_root" ]]; then
        docker_root="/var/lib/docker"
    fi

    if [[ -d "$docker_root" ]]; then
        usage_percent=$(df "$docker_root" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')

        if [[ -n "$usage_percent" ]]; then
            if [[ $usage_percent -ge 90 ]]; then
                RESULTS["docker_disk"]="error|${usage_percent}% used (critical)"
                ((ERRORS++))
            elif [[ $usage_percent -ge 80 ]]; then
                RESULTS["docker_disk"]="warning|${usage_percent}% used"
                ((WARNINGS++))
            else
                RESULTS["docker_disk"]="ok|${usage_percent}% used"
            fi
            return
        fi
    fi

    RESULTS["docker_disk"]="ok|Cannot determine"
}

check_docker_network() {
    # Check if bridge network is available
    if docker network ls 2>/dev/null | grep -q "bridge"; then
        RESULTS["docker_network"]="ok|Bridge network available"
    else
        RESULTS["docker_network"]="warning|Default bridge network not found"
        ((WARNINGS++))
    fi
}

# =============================================================================
# Helper Functions
# =============================================================================

version_compare() {
    # Returns 0 if $1 >= $2
    local v1="$1"
    local v2="$2"

    # Simple version comparison using sort -V
    if [[ "$(printf '%s\n' "$v2" "$v1" | sort -V | head -n1)" == "$v2" ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Main Function
# =============================================================================

run_docker_checks() {
    log_debug "Running Docker checks..."

    check_docker_installed
    if [[ $? -eq 0 ]]; then
        check_docker_daemon
        if [[ $? -eq 0 ]]; then
            check_docker_compose
            check_docker_socket
            check_docker_disk
            check_docker_network
        fi
    fi
}
