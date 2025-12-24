# Olivenet TTS - Operations Guide

This document serves as a guide for daily operations of the Olivenet TTS deployment.

## Quick Reference

| Operation | Command |
|-----------|---------|
| Stack status | `docker-compose ps` |
| View logs | `docker-compose logs -f stack` |
| Health check | `./scripts/health-check.sh` |
| Manual backup | `./scripts/backup.sh` |
| Restore | `./scripts/restore.sh <backup.tar.gz>` |

---

## Directory Structure

```
/opt/olivenet-tts/
└── deploy/olivenet/
    ├── docker-compose.yml      # Production stack
    ├── docker-compose.dev.yml  # Development stack
    ├── .env                    # Environment variables
    ├── config/
    │   ├── ttn-lw-stack.yml    # TTS configuration
    │   └── alert.conf          # Alert configuration
    ├── scripts/
    │   ├── backup.sh           # Full backup
    │   ├── restore.sh          # Restore from backup
    │   ├── backup-cron.sh      # Cron wrapper
    │   ├── health-check.sh     # Health checks
    │   ├── monitor-daemon.sh   # Monitoring daemon
    │   ├── alert.sh            # Alert utility
    │   ├── status-page.sh      # Status page generator
    │   └── lib/
    │       └── common.sh       # Shared functions
    └── systemd/
        ├── olivenet-tts-monitor.service
        ├── olivenet-tts-backup.service
        └── olivenet-tts-backup.timer
```

---

## Backup Operations

### Manual Backup

```bash
# Full backup
./scripts/backup.sh

# Database only
./scripts/backup.sh --db-only

# Config only
./scripts/backup.sh --config-only

# Custom retention period
./scripts/backup.sh --retention 14
```

### Scheduled Backup

Backups run daily at 02:00. Timer status:

```bash
# Timer status
sudo systemctl status olivenet-tts-backup.timer

# Next run time
sudo systemctl list-timers olivenet-tts-backup.timer

# Manual trigger
sudo systemctl start olivenet-tts-backup.service
```

### Backup Location

```
/var/backups/olivenet-tts/
├── daily/
│   ├── backup-20250120-020000.tar.gz
│   └── backup-20250121-020000.tar.gz
├── weekly/
│   └── backup-20250119-020000.tar.gz
├── logs/
│   └── backup.log
└── .latest -> daily/backup-20250121-020000.tar.gz
```

### Backup Contents

```bash
# List backup contents
./scripts/restore.sh --list backup-20250120-020000.tar.gz
```

---

## Restore Operations

### Full Restore

```bash
# Restore from latest backup
./scripts/restore.sh

# Restore from specific backup
./scripts/restore.sh backup-20250120-020000.tar.gz

# Dry-run (without making changes)
./scripts/restore.sh --dry-run backup-20250120-020000.tar.gz
```

### Partial Restore

```bash
# Database only
./scripts/restore.sh --db-only backup-20250120-020000.tar.gz

# Config only
./scripts/restore.sh --config-only backup-20250120-020000.tar.gz
```

### Important Notes

- Current state is automatically backed up before restore
- Can be skipped with `--skip-pre-backup` (not recommended)
- Stack is automatically restarted after restore

---

## Health Check

### Manual Check

```bash
# All checks
./scripts/health-check.sh

# JSON output
./scripts/health-check.sh --json

# Specific component
./scripts/health-check.sh --component stack
./scripts/health-check.sh --component postgres
./scripts/health-check.sh --component redis
```

### Checked Components

| Component | Check | Threshold |
|-----------|-------|-----------|
| stack | /healthz endpoint | HTTP 200 |
| postgres | pg_isready | Connection count < 180 |
| redis | PING | Memory usage |
| disk | df | 80% usage |
| memory | free | 85% usage |
| docker | container status | All running |
| ssl | certificate expiry | 30 days |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Healthy |
| 1 | Degraded (warnings) |
| 2 | Critical (errors) |

---

## Monitoring

### Starting the Daemon

```bash
# Start daemon
./scripts/monitor-daemon.sh start

# Check status
./scripts/monitor-daemon.sh status

# Stop
./scripts/monitor-daemon.sh stop

# Restart
./scripts/monitor-daemon.sh restart
```

### Management with Systemd

```bash
# Service status
sudo systemctl status olivenet-tts-monitor

# View logs
sudo journalctl -u olivenet-tts-monitor -f

# Restart
sudo systemctl restart olivenet-tts-monitor
```

### Monitoring Features

- Health check every 60 seconds
- Alert after 3 consecutive failures
- Recovery alert when restored
- Status file: `/var/run/olivenet-tts-monitor.status`

---

## Alert System

### Alert Channels

1. **Telegram** - Instant notification
2. **Email** - Detailed report
3. **Webhook** - Integrations (Slack, Discord, PagerDuty)

### Configuration

```bash
# Create config file
cp config/alert.conf.example config/alert.conf
chmod 600 config/alert.conf

# Edit required values
vim config/alert.conf
```

### Manual Alert Sending

```bash
# Telegram
./scripts/alert.sh --telegram "Test message"

# Email
./scripts/alert.sh --email admin@olivenet.com "Test message"

# Webhook
./scripts/alert.sh --webhook "https://hooks.slack.com/..." "Test message"

# All channels
./scripts/alert.sh --all "Test message to all channels"
```

---

## Status Page

### Generation

```bash
# Default location (/var/www/status)
./scripts/status-page.sh

# Custom location
./scripts/status-page.sh --output /var/www/html/status
```

### Nginx Configuration

```nginx
server {
    listen 80;
    server_name status.olivenet.com;

    location / {
        root /var/www/status;
        index index.html;
    }
}
```

### Automatic Updates

Status page auto-refreshes every 60 seconds. For periodic updates, use cron:

```cron
* * * * * /opt/olivenet-tts/deploy/olivenet/scripts/status-page.sh
```

---

## Log Management

### Log Locations

| Log | Location |
|-----|----------|
| Stack logs | `docker-compose logs stack` |
| Backup logs | `/var/log/olivenet-tts/backup.log` |
| Monitor logs | `journalctl -u olivenet-tts-monitor` |
| Cron logs | `/var/log/olivenet-tts/backup-cron.log` |

### Log Filtering

```bash
# Last 100 lines
docker-compose logs --tail=100 stack

# Specific time range
docker-compose logs --since="2025-01-20" stack

# Error filtering
docker-compose logs stack 2>&1 | grep -i error
```

### Log Rotation

Docker log rotation is configured in docker-compose.yml:
- Max size: 100MB
- Max files: 5

---

## Daily Operations

### Morning Checks

1. Run health check: `./scripts/health-check.sh`
2. Verify last backup: `ls -la /var/backups/olivenet-tts/.latest`
3. Check disk usage: `df -h`
4. Search for errors in logs: `docker-compose logs --since="24h" stack | grep -i error`

### Weekly Tasks

1. Backup integrity test: `./scripts/restore.sh --dry-run $(readlink /var/backups/olivenet-tts/.latest)`
2. SSL certificate check: `./scripts/health-check.sh --component ssl`
3. Disk cleanup: Delete old logs

### Deployment

```bash
# Pull latest
git pull origin main

# Pull images
docker-compose pull

# Update stack
docker-compose up -d

# Migration (if needed)
docker-compose exec stack ttn-lw-stack is-db migrate
```

---

## Troubleshooting

For detailed troubleshooting: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

### Quick Solutions

**Stack not starting:**
```bash
docker-compose logs stack | tail -50
docker-compose down && docker-compose up -d
```

**Database connection error:**
```bash
docker-compose exec postgres pg_isready -U ttn
docker-compose restart postgres
```

**Redis connection error:**
```bash
docker-compose exec redis redis-cli PING
docker-compose restart redis
```

**Insufficient memory:**
```bash
docker stats
docker system prune -a
```

---

## CI/CD

GitHub Actions workflows:

| Workflow | Trigger | Operation |
|----------|---------|-----------|
| ci.yml | Push/PR | Lint, test, build |
| deploy.yml | Manual/Tag | Deploy to server |
| release.yml | Release | Build & publish |
| scheduled.yml | Cron | Security scan, backup verify |

### Manual Deployment

```bash
# Via GitHub Actions
# Actions > Deploy > Run workflow

# Or directly on server
cd /opt/olivenet-tts
git pull
cd deploy/olivenet
docker-compose pull && docker-compose up -d
```

### Rollback

```bash
# Revert to previous commit
git checkout HEAD~1
docker-compose up -d

# Or to specific tag
git checkout v1.0.0
docker-compose up -d
```

---

## Related Documents

- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [DEPLOYMENT.md](DEPLOYMENT.md) - Installation guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Troubleshooting guide
- [GITHUB-SECRETS.md](GITHUB-SECRETS.md) - CI/CD configuration
- [CONFIG-VALIDATION-REPORT.md](CONFIG-VALIDATION-REPORT.md) - Config validation
