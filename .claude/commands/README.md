# Claude Code Custom Commands - Olivenet TTS

This directory contains custom Claude Code commands for TTS management.

## Usage

Commands are invoked with the "/" prefix:

```
/deploy          - Deploy TTS
/status          - Show system status
/test            - Run tests
/backup          - Create backup
/restore         - Restore from backup
/logs            - Show logs
/troubleshoot    - Troubleshooting
/device          - Device management
/gateway         - Gateway management
/simulate        - Run simulator
```

## Command Details

Each command can accept sub-parameters:

```bash
/deploy --check      # Only run preflight check
/deploy --dry-run    # Show what would be done, don't execute
/status --json       # JSON format output
/test gateway        # Gateway test only
/logs ns --tail 100  # Network Server last 100 logs
```

## Command List

| Command | File | Description |
|---------|------|-------------|
| /deploy | deploy.md | Stack deployment and updates |
| /status | status.md | System status and health check |
| /test | test.md | Run tests |
| /backup | backup.md | Create backup |
| /restore | restore.md | Restore from backup |
| /logs | logs.md | Log viewing |
| /troubleshoot | troubleshoot.md | Troubleshooting |
| /device | device.md | Device management |
| /gateway | gateway.md | Gateway management |
| /simulate | simulate.md | Run simulator |

## Related Skills

These commands are integrated with the following skills:

- `@troubleshooting` - Troubleshooting guide
- `@device-management` - Device management procedures
- `@gateway-management` - Gateway management procedures
- `@database-operations` - Backup/restore operations

## Directory Structure

```
.claude/commands/
├── README.md           # This file
├── deploy.md           # /deploy command
├── status.md           # /status command
├── test.md             # /test command
├── backup.md           # /backup command
├── restore.md          # /restore command
├── logs.md             # /logs command
├── troubleshoot.md     # /troubleshoot command
├── device.md           # /device command
├── gateway.md          # /gateway command
└── simulate.md         # /simulate command
```
