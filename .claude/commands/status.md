# /status Command

Shows system status.

## Parameters

| Parameter | Description |
|-----------|-------------|
| --json | JSON format output |
| --watch | Continuous update (5s) |
| --component NAME | Specific component (stack, postgres, redis) |

## Procedure

### 1. Run Health Check

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/scripts
./health-check.sh
```

For JSON format:
```bash
./health-check.sh --json
```

### 2. Container Status

```bash
docker compose ps
```

### 3. Resource Usage

```bash
docker stats --no-stream
```

### 4. Disk Usage

```bash
df -h /var/lib/docker
du -sh ./data/*
```

### 5. Recent Errors

```bash
docker compose logs --tail 50 | grep -i error
```

### 6. Stack Metrics (API)

```bash
curl -s http://localhost:1885/healthz
```

## Expected Output

```
+======================================================+
|              TTS Status - Olivenet                   |
+======================================================+
| Stack:      ✓ Running (uptime: 5d 12h 34m)          |
| PostgreSQL: ✓ Running                                |
| Redis:      ✓ Running                                |
+------------------------------------------------------+
| Resources                                            |
+------------------------------------------------------+
| CPU:    12% | Memory: 2.4GB/8GB | Disk: 45GB/100GB  |
+------------------------------------------------------+
| Stack Components                                     |
+------------------------------------------------------+
| Identity Server:    ✓ Healthy                        |
| Gateway Server:     ✓ Healthy (2 gateways connected) |
| Network Server:     ✓ Healthy                        |
| Application Server: ✓ Healthy                        |
| Join Server:        ✓ Healthy                        |
+------------------------------------------------------+
| Statistics (24h)                                     |
+------------------------------------------------------+
| Uplinks:   125,432 | Downlinks: 8,234 | Joins: 45   |
+------------------------------------------------------+
| Last Backup: 2025-01-22 02:00 (6 hours ago)         |
+======================================================+
```

## Component Details

### stack
- HTTP API health
- gRPC connectivity
- Memory usage

### postgres
- Connection count
- Database size
- Replication status (if configured)

### redis
- Memory usage
- Connection count
- Keyspace info

## Related Commands

- `/logs` - Detailed log viewing
- `/troubleshoot` - Troubleshooting
