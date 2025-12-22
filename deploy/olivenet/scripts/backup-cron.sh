#!/bin/bash
# =============================================================================
# Olivenet TTS - Cron Backup Wrapper
# =============================================================================
# Cron-friendly wrapper for backup.sh
#
# Features:
#   - Silent mode (only output on error)
#   - Lock file to prevent concurrent runs
#   - Email/Telegram notification on failure
#   - Proper exit codes for cron
#
# Usage in crontab:
#   # Daily backup at 2:00 AM
#   0 2 * * * /opt/olivenet-tts/deploy/olivenet/scripts/backup-cron.sh
#
#   # With email notification
#   MAILTO=admin@olivenet.com
#   0 2 * * * /opt/olivenet-tts/deploy/olivenet/scripts/backup-cron.sh
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
CONFIG_FILE="${SCRIPT_DIR}/../config/alert.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default configuration
BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"
ALERT_SCRIPT="${SCRIPT_DIR}/alert.sh"
LOG_DIR="${LOG_DIR:-/var/log/olivenet-tts}"
LOCK_FILE="/var/run/olivenet-tts-backup-cron.lock"

# Create log directory
mkdir -p "$LOG_DIR"

# Temporary file for capturing output
OUTPUT_FILE=$(mktemp)
trap "rm -f $OUTPUT_FILE $LOCK_FILE" EXIT

# =============================================================================
# Lock handling
# =============================================================================

# Check for existing lock
if [[ -f "$LOCK_FILE" ]]; then
    pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "Backup already running (PID: $pid)" >> "$LOG_DIR/backup-cron.log"
        exit 0  # Exit silently - not an error
    fi
    # Stale lock, remove it
    rm -f "$LOCK_FILE"
fi

# Create lock
echo $$ > "$LOCK_FILE"

# =============================================================================
# Run backup
# =============================================================================

# Get start time
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# Run backup and capture output
"$BACKUP_SCRIPT" --no-color > "$OUTPUT_FILE" 2>&1
EXIT_CODE=$?

# Get end time
END_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# =============================================================================
# Handle results
# =============================================================================

# Log the result
{
    echo "=========================================="
    echo "Backup Cron Run: $START_TIME"
    echo "Exit Code: $EXIT_CODE"
    echo "=========================================="
    cat "$OUTPUT_FILE"
    echo ""
} >> "$LOG_DIR/backup-cron.log"

# On failure, send alert and output to stderr (for cron MAILTO)
if [[ $EXIT_CODE -ne 0 ]]; then
    # Output to stderr for cron to capture
    echo "OLIVENET TTS BACKUP FAILED" >&2
    echo "Time: $START_TIME" >&2
    echo "Exit Code: $EXIT_CODE" >&2
    echo "" >&2
    echo "Output:" >&2
    cat "$OUTPUT_FILE" >&2

    # Send alert via alert.sh if available
    if [[ -x "$ALERT_SCRIPT" ]]; then
        ALERT_MESSAGE="TTS Backup Failed

Time: $START_TIME
Exit Code: $EXIT_CODE
Host: $(hostname)

Check logs: $LOG_DIR/backup-cron.log"

        "$ALERT_SCRIPT" --all "$ALERT_MESSAGE" 2>/dev/null || true
    fi
fi

# Rotate log file if too large (>10MB)
LOG_FILE="$LOG_DIR/backup-cron.log"
if [[ -f "$LOG_FILE" ]]; then
    LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
    if [[ $LOG_SIZE -gt 10485760 ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        gzip "${LOG_FILE}.old" 2>/dev/null || true
    fi
fi

exit $EXIT_CODE
