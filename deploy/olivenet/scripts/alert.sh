#!/bin/bash
# =============================================================================
# Olivenet TTS - Alert Script
# =============================================================================
# Send alerts via various channels
#
# Channels:
#   - Telegram
#   - Email (via sendmail/msmtp)
#   - Webhook (generic HTTP POST)
#
# Usage:
#   ./alert.sh --telegram "Message here"
#   ./alert.sh --email "admin@olivenet.com" "Message"
#   ./alert.sh --webhook "https://..." "Message"
#   ./alert.sh --all "Message to all channels"
# =============================================================================

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# Configuration
# =============================================================================

# Load config file if exists
CONFIG_FILE="${SCRIPT_DIR}/../config/alert.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Telegram settings
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# Email settings
EMAIL_RECIPIENT="${EMAIL_RECIPIENT:-}"
EMAIL_FROM="${EMAIL_FROM:-noreply@olivenet.com}"
SMTP_CMD="${SMTP_CMD:-sendmail}"  # or msmtp

# Webhook settings
WEBHOOK_URL="${WEBHOOK_URL:-}"
WEBHOOK_METHOD="${WEBHOOK_METHOD:-POST}"

# =============================================================================
# Help
# =============================================================================

show_help() {
    show_help_header "alert.sh" "Send alerts via various channels"

    cat << EOF
${BOLD}Usage:${NC}
    $0 --telegram "Message"
    $0 --email "recipient@email.com" "Message"
    $0 --webhook "https://..." "Message"
    $0 --all "Message to all configured channels"

${BOLD}Options:${NC}
    --telegram          Send via Telegram
    --email ADDRESS     Send via email
    --webhook URL       Send via HTTP webhook
    --all               Send to all configured channels
    --subject SUBJECT   Email subject (default: TTS Alert)
    --config FILE       Use custom config file

EOF
    show_common_options

    cat << EOF
${BOLD}Configuration:${NC}
    Config file: $CONFIG_FILE

    Required environment variables or config:
    - TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID (for Telegram)
    - EMAIL_RECIPIENT (for email)
    - WEBHOOK_URL (for webhook)

${BOLD}Examples:${NC}
    $0 --telegram "Server is down!"
    $0 --email admin@olivenet.com "Backup completed"
    $0 --all "Deployment finished"

EOF
}

# =============================================================================
# Alert Functions
# =============================================================================

send_telegram() {
    local message="$1"

    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        log_error "Telegram not configured (missing BOT_TOKEN or CHAT_ID)"
        return 1
    fi

    log_debug "Sending Telegram message..."

    local response
    response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "parse_mode=HTML" \
        -d "text=$(echo -e "<b>Olivenet TTS Alert</b>\n\n${message}" | head -c 4000)" \
        2>/dev/null)

    if echo "$response" | grep -q '"ok":true'; then
        log_success "Telegram message sent"
        return 0
    else
        log_error "Telegram send failed: $response"
        return 1
    fi
}

send_email() {
    local recipient="$1"
    local message="$2"
    local subject="${EMAIL_SUBJECT:-TTS Alert}"

    if [[ -z "$recipient" ]]; then
        recipient="$EMAIL_RECIPIENT"
    fi

    if [[ -z "$recipient" ]]; then
        log_error "No email recipient specified"
        return 1
    fi

    log_debug "Sending email to $recipient..."

    # Create email content
    local email_content
    email_content=$(cat << EOF
From: $EMAIL_FROM
To: $recipient
Subject: $subject
Content-Type: text/plain; charset=UTF-8

Olivenet TTS Alert
==================

$message

--
Sent from $(hostname) at $(date)
EOF
)

    # Try to send
    if command -v "$SMTP_CMD" &> /dev/null; then
        echo "$email_content" | "$SMTP_CMD" -t
        if [[ $? -eq 0 ]]; then
            log_success "Email sent to $recipient"
            return 0
        else
            log_error "Email send failed"
            return 1
        fi
    elif command -v mail &> /dev/null; then
        echo "$message" | mail -s "$subject" -r "$EMAIL_FROM" "$recipient"
        if [[ $? -eq 0 ]]; then
            log_success "Email sent to $recipient"
            return 0
        else
            log_error "Email send failed"
            return 1
        fi
    else
        log_error "No email command available (tried $SMTP_CMD, mail)"
        return 1
    fi
}

send_webhook() {
    local url="$1"
    local message="$2"

    if [[ -z "$url" ]]; then
        url="$WEBHOOK_URL"
    fi

    if [[ -z "$url" ]]; then
        log_error "No webhook URL specified"
        return 1
    fi

    log_debug "Sending webhook to $url..."

    # Create JSON payload
    local payload
    payload=$(cat << EOF
{
  "source": "olivenet-tts",
  "host": "$(hostname)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "message": "$(echo "$message" | sed 's/"/\\"/g' | tr '\n' ' ')"
}
EOF
)

    local response
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X "$WEBHOOK_METHOD" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url" 2>/dev/null)

    if [[ "$http_code" =~ ^2 ]]; then
        log_success "Webhook sent (HTTP $http_code)"
        return 0
    else
        log_error "Webhook failed (HTTP $http_code)"
        return 1
    fi
}

send_all() {
    local message="$1"
    local sent=0
    local failed=0

    log_info "Sending to all configured channels..."

    # Telegram
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        if send_telegram "$message"; then
            sent=$((sent + 1))
        else
            failed=$((failed + 1))
        fi
    fi

    # Email
    if [[ -n "$EMAIL_RECIPIENT" ]]; then
        if send_email "$EMAIL_RECIPIENT" "$message"; then
            sent=$((sent + 1))
        else
            failed=$((failed + 1))
        fi
    fi

    # Webhook
    if [[ -n "$WEBHOOK_URL" ]]; then
        if send_webhook "$WEBHOOK_URL" "$message"; then
            sent=$((sent + 1))
        else
            failed=$((failed + 1))
        fi
    fi

    if [[ $sent -eq 0 ]]; then
        log_error "No alerts sent (sent: $sent, failed: $failed)"
        return 1
    elif [[ $failed -gt 0 ]]; then
        log_warn "Some alerts failed (sent: $sent, failed: $failed)"
        return 0
    else
        log_success "All alerts sent (sent: $sent)"
        return 0
    fi
}

# =============================================================================
# Argument Parsing
# =============================================================================

main() {
    local mode=""
    local target=""
    local message=""

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
            --config)
                CONFIG_FILE="$2"
                if [[ -f "$CONFIG_FILE" ]]; then
                    source "$CONFIG_FILE"
                fi
                shift 2
                ;;
            --subject)
                EMAIL_SUBJECT="$2"
                shift 2
                ;;
            --telegram)
                mode="telegram"
                message="$2"
                shift 2
                ;;
            --email)
                mode="email"
                target="$2"
                message="$3"
                shift 3
                ;;
            --webhook)
                mode="webhook"
                target="$2"
                message="$3"
                shift 3
                ;;
            --all)
                mode="all"
                message="$2"
                shift 2
                ;;
            *)
                # Assume remaining args are the message
                message="$*"
                break
                ;;
        esac
    done

    if [[ -z "$mode" ]]; then
        log_error "No channel specified"
        show_help
        exit 2
    fi

    if [[ -z "$message" ]]; then
        log_error "No message specified"
        exit 2
    fi

    case $mode in
        telegram)
            send_telegram "$message"
            ;;
        email)
            send_email "$target" "$message"
            ;;
        webhook)
            send_webhook "$target" "$message"
            ;;
        all)
            send_all "$message"
            ;;
    esac
}

main "$@"
