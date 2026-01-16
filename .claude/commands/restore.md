# /restore Command

Restores system from backup.

## Parameters

| Parameter | Description |
|-----------|-------------|
| --latest | Use latest backup |
| --file PATH | Specific backup file |
| --dry-run | Show what would be done, don't execute |
| --db-only | Database restore only |
| --config-only | Config restore only |
| --force | Restore without confirmation |

## Procedure

### Restore from Latest Backup

```bash
cd /opt/lorawan-stack/deploy/olivenet/scripts
./restore.sh --latest --dry-run  # Check first
./restore.sh --latest            # Actual restore
```

### Restore from Specific Backup

```bash
# List available backups
ls -la /var/backups/olivenet-tts/daily/

# Restore specific backup
./restore.sh --file /var/backups/olivenet-tts/daily/backup-20250120-100000.tar.gz
```

## Restore Process

1. **Pre-restore Safety Backup**
   - Current state is backed up
   - Rollback possible

2. **Stop Stack**
```bash
docker compose down
```

3. **Database Restore**
   - PostgreSQL dump loading
   - Foreign key checks

4. **Redis Restore**
   - RDB file loading

5. **Config Restore**
   - .env, YAML files

6. **Start Stack**
```bash
docker compose up -d
```

7. **Verification**
```bash
./health-check.sh
```

## Dry-Run Output

```
[DRY-RUN] Restore from: backup-20250120-100000.tar.gz

Actions to perform:
1. Create safety backup of current state
2. Stop TTS stack
3. Restore PostgreSQL database (156MB)
4. Restore Redis data (12MB)
5. Restore configuration files
6. Start TTS stack
7. Run health check

Estimated time: 2-5 minutes

Run without --dry-run to execute.
```

## Warnings

⚠️ **CAUTION:**
- Restore operation deletes existing data
- Be careful in production
- Test with `--dry-run` first

## Error States

| Error | Solution |
|-------|----------|
| Backup file not found | Check path |
| Permission denied | Run as root |
| Database restore failed | Check backup integrity |
| Stack won't start | Check logs, rollback |

## Rollback

If restore fails:

```bash
./restore.sh --file /var/backups/olivenet-tts/pre-restore-safety.tar.gz
```

## Related Commands

- `/backup` - Create backup
- `/status` - Status check after restore
