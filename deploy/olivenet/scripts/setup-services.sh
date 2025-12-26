#!/bin/bash
#
# Olivenet TTS - Post-Deployment Service Setup
# Sets up systemd services for backup and monitoring
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo)"
    exit 1
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Olivenet TTS - Service Setup                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Step 1: Create Directories
# =============================================================================
log_info "Creating required directories..."

mkdir -p /var/log/olivenet-tts
mkdir -p /var/backups/olivenet-tts/daily
mkdir -p /var/run

# Set permissions - allow docker group
chown root:docker /var/log/olivenet-tts 2>/dev/null || chown root:root /var/log/olivenet-tts
chmod 775 /var/log/olivenet-tts
chown root:docker /var/backups/olivenet-tts 2>/dev/null || chown root:root /var/backups/olivenet-tts
chmod 775 /var/backups/olivenet-tts

log_ok "Directories created"

# =============================================================================
# Step 2: Install Systemd Services
# =============================================================================
log_info "Installing systemd services..."

SYSTEMD_DIR="$DEPLOY_DIR/systemd"

if [[ ! -d "$SYSTEMD_DIR" ]]; then
    log_error "Systemd directory not found: $SYSTEMD_DIR"
    exit 1
fi

# Copy service files
if [[ -f "$SYSTEMD_DIR/olivenet-tts-backup.service" ]]; then
    cp "$SYSTEMD_DIR/olivenet-tts-backup.service" /etc/systemd/system/
    log_ok "Installed olivenet-tts-backup.service"
else
    log_warn "olivenet-tts-backup.service not found"
fi

if [[ -f "$SYSTEMD_DIR/olivenet-tts-backup.timer" ]]; then
    cp "$SYSTEMD_DIR/olivenet-tts-backup.timer" /etc/systemd/system/
    log_ok "Installed olivenet-tts-backup.timer"
else
    log_warn "olivenet-tts-backup.timer not found"
fi

if [[ -f "$SYSTEMD_DIR/olivenet-tts-monitor.service" ]]; then
    cp "$SYSTEMD_DIR/olivenet-tts-monitor.service" /etc/systemd/system/
    log_ok "Installed olivenet-tts-monitor.service"
else
    log_warn "olivenet-tts-monitor.service not found"
fi

# Reload systemd
systemctl daemon-reload

log_ok "Systemd services installed"

# =============================================================================
# Step 3: Enable Backup Timer
# =============================================================================
log_info "Enabling backup timer..."

if systemctl list-unit-files olivenet-tts-backup.timer &>/dev/null; then
    systemctl enable olivenet-tts-backup.timer
    systemctl start olivenet-tts-backup.timer
    log_ok "Backup timer enabled (daily at 02:00)"
else
    log_warn "Backup timer not available"
fi

# =============================================================================
# Step 4: Monitor Daemon (Optional)
# =============================================================================
echo ""
read -p "Enable health monitor daemon? [y/N]: " enable_monitor
enable_monitor=${enable_monitor:-N}

if [[ "$enable_monitor" =~ ^[Yy]$ ]]; then
    # Check for alert config
    if [[ -f "$DEPLOY_DIR/config/alert.conf" ]]; then
        log_info "Enabling monitor daemon..."
        systemctl enable olivenet-tts-monitor
        systemctl start olivenet-tts-monitor
        log_ok "Monitor daemon started"
    else
        log_warn "Alert config not found. Creating from template..."
        if [[ -f "$DEPLOY_DIR/config/alert.conf.example" ]]; then
            cp "$DEPLOY_DIR/config/alert.conf.example" "$DEPLOY_DIR/config/alert.conf"
            chmod 600 "$DEPLOY_DIR/config/alert.conf"
            log_info "Created $DEPLOY_DIR/config/alert.conf"
            log_info "Edit the config file and configure your alert channels, then run:"
            log_info "  sudo systemctl enable olivenet-tts-monitor"
            log_info "  sudo systemctl start olivenet-tts-monitor"
        else
            log_warn "Alert config template not found"
            cat > "$DEPLOY_DIR/config/alert.conf" << 'EOF'
# Olivenet TTS Alert Configuration
# Uncomment and configure the channels you want to use

# Telegram (recommended)
# Create bot via @BotFather, get chat_id via @userinfobot
#TELEGRAM_BOT_TOKEN=your_bot_token
#TELEGRAM_CHAT_ID=your_chat_id

# Email (requires sendmail/postfix)
#EMAIL_RECIPIENT=admin@yourdomain.com
#EMAIL_FROM=tts@yourdomain.com

# Webhook (Slack, Discord, etc.)
#WEBHOOK_URL=https://hooks.slack.com/services/xxx
EOF
            chmod 600 "$DEPLOY_DIR/config/alert.conf"
            log_info "Created basic alert.conf template"
            log_info "Edit $DEPLOY_DIR/config/alert.conf then run:"
            log_info "  sudo systemctl enable olivenet-tts-monitor"
            log_info "  sudo systemctl start olivenet-tts-monitor"
        fi
    fi
else
    log_info "Monitor daemon skipped. Enable later with:"
    log_info "  sudo systemctl enable olivenet-tts-monitor"
    log_info "  sudo systemctl start olivenet-tts-monitor"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   SERVICE SETUP COMPLETE                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Installed Services:${NC}"
echo ""

# Show timer status
echo "  Backup Timer:"
if systemctl is-active olivenet-tts-backup.timer &>/dev/null; then
    echo -e "    Status: ${GREEN}active${NC}"
    echo "    Next run: $(systemctl list-timers olivenet-tts-backup.timer --no-pager 2>/dev/null | grep olivenet | awk '{print $1, $2, $3}' || echo 'Check with: systemctl list-timers')"
else
    echo -e "    Status: ${YELLOW}inactive${NC}"
fi
echo ""

# Show monitor status
echo "  Monitor Daemon:"
if systemctl is-active olivenet-tts-monitor &>/dev/null; then
    echo -e "    Status: ${GREEN}active${NC}"
else
    echo -e "    Status: ${YELLOW}not running${NC}"
fi
echo ""

echo -e "${BLUE}Useful Commands:${NC}"
echo ""
echo "  # Manual backup"
echo "  sudo $SCRIPT_DIR/backup.sh"
echo ""
echo "  # Check backup timer"
echo "  systemctl list-timers olivenet-tts-backup.timer"
echo ""
echo "  # View backup logs"
echo "  journalctl -u olivenet-tts-backup -f"
echo ""
echo "  # Monitor status"
echo "  systemctl status olivenet-tts-monitor"
echo ""
echo "  # View monitor logs"
echo "  journalctl -u olivenet-tts-monitor -f"
echo ""
