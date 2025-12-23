#!/bin/bash
# =============================================================================
# Olivenet TTS - System Pre-flight Checks
# =============================================================================
# Checks system requirements: OS, CPU, RAM, Disk, Swap
# =============================================================================

# Minimum requirements
MIN_CPU_CORES=2
MIN_RAM_GB=4
MIN_DISK_GB=20
MIN_SWAP_GB=1

# Recommended requirements
REC_CPU_CORES=4
REC_RAM_GB=8
REC_DISK_GB=50
REC_SWAP_GB=2

# =============================================================================
# Check Functions
# =============================================================================

check_os_version() {
    local os_name=""
    local os_version=""
    local os_id=""

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        os_name="$NAME"
        os_version="$VERSION_ID"
        os_id="$ID"
    elif [[ -f /etc/lsb-release ]]; then
        # shellcheck source=/dev/null
        source /etc/lsb-release
        os_name="$DISTRIB_DESCRIPTION"
        os_version="$DISTRIB_RELEASE"
        os_id="$DISTRIB_ID"
    else
        RESULTS["os_version"]="error|Cannot detect OS"
        ERRORS=$((ERRORS + 1))
        return
    fi

    # Check supported OS
    case "$os_id" in
        ubuntu)
            if [[ $(echo "$os_version >= 20.04" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
                RESULTS["os_version"]="ok|$os_name $os_version"
            else
                RESULTS["os_version"]="warning|$os_name $os_version (Ubuntu 20.04+ recommended)"
                WARNINGS=$((WARNINGS + 1))
            fi
            ;;
        debian)
            if [[ $(echo "$os_version >= 11" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
                RESULTS["os_version"]="ok|$os_name $os_version"
            else
                RESULTS["os_version"]="warning|$os_name $os_version (Debian 11+ recommended)"
                WARNINGS=$((WARNINGS + 1))
            fi
            ;;
        *)
            RESULTS["os_version"]="warning|$os_name $os_version (Ubuntu/Debian recommended)"
            WARNINGS=$((WARNINGS + 1))
            ;;
    esac
}

check_cpu_cores() {
    local cores
    cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "0")

    if [[ $cores -lt $MIN_CPU_CORES ]]; then
        RESULTS["cpu_cores"]="error|$cores cores (minimum $MIN_CPU_CORES required)"
        ERRORS=$((ERRORS + 1))
    elif [[ $cores -lt $REC_CPU_CORES ]]; then
        RESULTS["cpu_cores"]="warning|$cores cores ($REC_CPU_CORES recommended)"
        WARNINGS=$((WARNINGS + 1))
    else
        RESULTS["cpu_cores"]="ok|$cores cores"
    fi
}

check_ram() {
    local total_kb
    local total_gb

    if [[ -f /proc/meminfo ]]; then
        total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        total_gb=$((total_kb / 1024 / 1024))
    else
        total_gb=0
    fi

    # Get available memory
    local available_kb
    local available_gb
    available_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [[ -z "$available_kb" ]]; then
        available_kb=$(grep -E "MemFree|Buffers|Cached" /proc/meminfo | awk '{sum+=$2} END {print sum}')
    fi
    available_gb=$((available_kb / 1024 / 1024))

    if [[ $total_gb -lt $MIN_RAM_GB ]]; then
        RESULTS["ram"]="error|${total_gb}GB total (minimum ${MIN_RAM_GB}GB required)"
        ERRORS=$((ERRORS + 1))
    elif [[ $total_gb -lt $REC_RAM_GB ]]; then
        RESULTS["ram"]="warning|${total_gb}GB total (${REC_RAM_GB}GB recommended)"
        WARNINGS=$((WARNINGS + 1))
    else
        RESULTS["ram"]="ok|${total_gb}GB total, ${available_gb}GB available"
    fi
}

check_disk_space() {
    local mount_point="${1:-/}"
    local available_gb

    available_gb=$(df -BG "$mount_point" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G')

    if [[ -z "$available_gb" || "$available_gb" == "0" ]]; then
        RESULTS["disk_space"]="error|Cannot determine disk space"
        ERRORS=$((ERRORS + 1))
        return
    fi

    if [[ $available_gb -lt $MIN_DISK_GB ]]; then
        RESULTS["disk_space"]="error|${available_gb}GB free (minimum ${MIN_DISK_GB}GB required)"
        ERRORS=$((ERRORS + 1))
    elif [[ $available_gb -lt $REC_DISK_GB ]]; then
        RESULTS["disk_space"]="warning|${available_gb}GB free (${REC_DISK_GB}GB recommended)"
        WARNINGS=$((WARNINGS + 1))
    else
        RESULTS["disk_space"]="ok|${available_gb}GB free"
    fi
}

check_swap() {
    local swap_total_kb
    local swap_total_gb

    swap_total_kb=$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    swap_total_gb=$((swap_total_kb / 1024 / 1024))

    if [[ $swap_total_gb -lt $MIN_SWAP_GB ]]; then
        RESULTS["swap"]="warning|${swap_total_gb}GB (${REC_SWAP_GB}GB+ recommended)"
        WARNINGS=$((WARNINGS + 1))
    else
        RESULTS["swap"]="ok|${swap_total_gb}GB"
    fi
}

check_time_sync() {
    # Check if time synchronization is configured
    local sync_status="unknown"

    if command -v timedatectl &>/dev/null; then
        if timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
            sync_status="synchronized"
            RESULTS["time_sync"]="ok|Time synchronized (timedatectl)"
            return
        elif timedatectl status 2>/dev/null | grep -q "NTP service: active"; then
            sync_status="active"
            RESULTS["time_sync"]="ok|NTP service active"
            return
        fi
    fi

    if systemctl is-active chronyd &>/dev/null; then
        RESULTS["time_sync"]="ok|chronyd active"
        return
    fi

    if systemctl is-active ntp &>/dev/null; then
        RESULTS["time_sync"]="ok|ntp active"
        return
    fi

    if systemctl is-active systemd-timesyncd &>/dev/null; then
        RESULTS["time_sync"]="ok|systemd-timesyncd active"
        return
    fi

    RESULTS["time_sync"]="warning|Time sync not detected (NTP recommended)"
    WARNINGS=$((WARNINGS + 1))
}

# =============================================================================
# Main Function
# =============================================================================

run_system_checks() {
    log_debug "Running system checks..."

    check_os_version || true
    check_cpu_cores || true
    check_ram || true
    check_disk_space "/" || true
    check_swap || true
    check_time_sync || true
}
