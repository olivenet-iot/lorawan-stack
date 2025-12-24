# /backup Command

Creates system backup.

## Parameters

| Parameter | Description |
|-----------|-------------|
| --db-only | Database backup only |
| --config-only | Config backup only |
| --full | Full backup (default) |
| --retention DAYS | Retention period (days) |
| --output DIR | Output directory |

## Procedure

### Full Backup

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/scripts
./backup.sh
```

### Database Only

```bash
./backup.sh --db-only
```

### Config Only

```bash
./backup.sh --config-only
```

### Custom Retention

```bash
./backup.sh --retention 30  # Keep for 30 days
```

## Backup Contents

Full backup includes:

1. **PostgreSQL Database**
   - All tables (pg_dump)
   - Users, organizations, applications, devices
   - API keys, sessions

2. **Redis Data**
   - RDB snapshot
   - Device state, session cache

3. **Configuration Files**
   - .env
   - docker-compose.yml
   - ttn-lw-stack.yml

4. **Blob Storage** (optional)
   - Profile pictures
   - Uploaded files

## Backup Location

```
/var/backups/olivenet-tts/
├── daily/
│   ├── backup-20250122-100000.tar.gz
│   └── backup-20250121-100000.tar.gz
├── weekly/
│   └── backup-20250120-020000.tar.gz
└── logs/
    └── backup.log
```

## Automated Backup

Automated backup with cron:

```bash
# Using systemd timer
systemctl status olivenet-tts-backup.timer
```

## Success Output

```
[2025-01-22 10:00:00] [INFO] Starting backup...
[2025-01-22 10:00:01] [INFO] Backing up PostgreSQL...
[2025-01-22 10:00:15] [INFO] Backing up Redis...
[2025-01-22 10:00:16] [INFO] Backing up configuration...
[2025-01-22 10:00:17] [INFO] Creating archive...
[2025-01-22 10:00:20] [SUCCESS] Backup completed: backup-20250122-100000.tar.gz (45MB)
[2025-01-22 10:00:20] [INFO] Cleaning old backups...
[2025-01-22 10:00:21] [INFO] Retention: 7 days, removed 2 old backups
```

## Related Commands

- `/restore` - Restore from backup
- `/status` - Last backup info

## Related Skill

- `@database-operations` - Detailed backup procedures
