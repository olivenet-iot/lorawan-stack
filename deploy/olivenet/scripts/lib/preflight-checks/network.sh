#!/bin/bash
# =============================================================================
# Olivenet TTS - Network Pre-flight Checks
# =============================================================================
# Checks network requirements: ports, DNS, connectivity
# =============================================================================

# Required ports
declare -A REQUIRED_PORTS=(
    ["1700/udp"]="Gateway UDP Packet Forwarder"
    ["1885/tcp"]="HTTP API"
    ["8885/tcp"]="HTTPS API"
    ["1884/tcp"]="gRPC"
    ["1883/tcp"]="MQTT"
    ["8883/tcp"]="MQTTS"
)

# =============================================================================
# Check Functions
# =============================================================================

check_port_available() {
    local port="$1"
    local protocol="${2:-tcp}"
    local description="${3:-}"

    local port_num="${port%%/*}"

    # Check if port is in use
    if [[ "$protocol" == "tcp" ]]; then
        if ss -tlnp 2>/dev/null | grep -q ":${port_num} "; then
            # Get process using the port
            local process
            process=$(ss -tlnp 2>/dev/null | grep ":${port_num} " | grep -oP 'users:\(\("\K[^"]+' | head -1)
            process="${process:-unknown}"
            RESULTS["port_${port_num}_${protocol}"]="error|Port ${port_num}/${protocol} in use by ${process}"
            ((ERRORS++))
            return 1
        fi
    elif [[ "$protocol" == "udp" ]]; then
        if ss -ulnp 2>/dev/null | grep -q ":${port_num} "; then
            local process
            process=$(ss -ulnp 2>/dev/null | grep ":${port_num} " | grep -oP 'users:\(\("\K[^"]+' | head -1)
            process="${process:-unknown}"
            RESULTS["port_${port_num}_${protocol}"]="error|Port ${port_num}/${protocol} in use by ${process}"
            ((ERRORS++))
            return 1
        fi
    fi

    RESULTS["port_${port_num}_${protocol}"]="ok|Available"
    return 0
}

check_all_required_ports() {
    log_debug "Checking required ports..."

    for port_proto in "${!REQUIRED_PORTS[@]}"; do
        local port="${port_proto%%/*}"
        local proto="${port_proto##*/}"
        local desc="${REQUIRED_PORTS[$port_proto]}"

        check_port_available "$port" "$proto" "$desc"
    done
}

check_dns_resolution() {
    local domain="${DOMAIN:-localhost}"

    # Skip for localhost
    if [[ "$domain" == "localhost" || "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        RESULTS["dns"]="ok|Using $domain (local)"
        return 0
    fi

    # Check DNS resolution
    if command -v dig &>/dev/null; then
        local ip
        ip=$(dig +short "$domain" 2>/dev/null | head -1)
        if [[ -n "$ip" ]]; then
            RESULTS["dns"]="ok|$domain -> $ip"
            return 0
        fi
    elif command -v nslookup &>/dev/null; then
        if nslookup "$domain" &>/dev/null; then
            RESULTS["dns"]="ok|$domain resolves"
            return 0
        fi
    elif command -v host &>/dev/null; then
        if host "$domain" &>/dev/null; then
            RESULTS["dns"]="ok|$domain resolves"
            return 0
        fi
    fi

    # Try getent as fallback
    if getent hosts "$domain" &>/dev/null; then
        RESULTS["dns"]="ok|$domain resolves"
        return 0
    fi

    RESULTS["dns"]="error|Cannot resolve $domain"
    ((ERRORS++))
    return 1
}

check_internet_connectivity() {
    # Check internet connectivity
    local test_urls=(
        "https://www.google.com"
        "https://cloudflare.com"
        "https://www.thethingsindustries.com"
    )

    for url in "${test_urls[@]}"; do
        if curl -s --connect-timeout 5 --max-time 10 -o /dev/null "$url" 2>/dev/null; then
            RESULTS["internet"]="ok|Connected"
            return 0
        fi
    done

    # Try with ping as fallback
    if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        RESULTS["internet"]="warning|Limited (DNS may be blocked)"
        ((WARNINGS++))
        return 0
    fi

    RESULTS["internet"]="warning|No internet connection detected"
    ((WARNINGS++))
    return 1
}

check_ipv4_forwarding() {
    local forwarding
    forwarding=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)

    if [[ "$forwarding" == "1" ]]; then
        RESULTS["ipv4_forward"]="ok|Enabled"
    else
        RESULTS["ipv4_forward"]="warning|Disabled (may affect Docker networking)"
        ((WARNINGS++))
    fi
}

check_firewall() {
    # Check if firewall is active
    local firewall_status="none"

    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        firewall_status="ufw (active)"
    elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q "running"; then
        firewall_status="firewalld (active)"
    elif command -v iptables &>/dev/null; then
        local rules
        rules=$(iptables -L INPUT -n 2>/dev/null | wc -l)
        if [[ $rules -gt 2 ]]; then
            firewall_status="iptables (rules present)"
        fi
    fi

    if [[ "$firewall_status" != "none" ]]; then
        RESULTS["firewall"]="ok|$firewall_status - ensure required ports are allowed"
    else
        RESULTS["firewall"]="warning|No firewall detected (consider enabling for production)"
        ((WARNINGS++))
    fi
}

# =============================================================================
# Main Function
# =============================================================================

run_network_checks() {
    log_debug "Running network checks..."

    check_all_required_ports
    check_dns_resolution
    check_internet_connectivity
    check_ipv4_forwarding
    check_firewall
}
