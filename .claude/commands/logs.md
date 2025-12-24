# /logs Command

Log viewing and analysis.

## Parameters

| Parameter | Description |
|-----------|-------------|
| stack | TTS stack logs |
| postgres | PostgreSQL logs |
| redis | Redis logs |
| all | All logs |
| --tail N | Last N lines |
| --since TIME | From specific time |
| --follow | Live follow |
| --filter TEXT | Filter text |

## Procedure

### Stack Logs

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet
docker compose logs stack --tail 100
```

Live follow:
```bash
docker compose logs -f stack
```

### Component Filtering

```bash
# Gateway Server logs
docker compose logs stack 2>&1 | grep "gs:"

# Network Server logs
docker compose logs stack 2>&1 | grep "ns:"

# Join Server logs
docker compose logs stack 2>&1 | grep "js:"

# Application Server logs
docker compose logs stack 2>&1 | grep "as:"

# Identity Server logs
docker compose logs stack 2>&1 | grep "is:"
```

### Device/Gateway Filtering

```bash
# Specific device
docker compose logs stack 2>&1 | grep "dev_eui=70B3D57ED0000001"

# Specific gateway
docker compose logs stack 2>&1 | grep "gateway_eui=AA555A0000000001"

# Specific application
docker compose logs stack 2>&1 | grep "application_id=my-app"
```

### Error Filtering

```bash
# Errors only
docker compose logs stack 2>&1 | grep -i error

# Errors and warnings
docker compose logs stack 2>&1 | grep -iE "error|warn"
```

### Time Filtering

```bash
# Last 1 hour
docker compose logs stack --since 1h

# From specific time
docker compose logs stack --since 2025-01-22T10:00:00
```

### PostgreSQL Logs

```bash
docker compose logs postgres --tail 50
```

### Redis Logs

```bash
docker compose logs redis --tail 50
```

## Log Format

TTS produces JSON format logs:

```json
{
  "level": "info",
  "msg": "Received uplink",
  "namespace": "ns",
  "dev_eui": "70B3D57ED0000001",
  "f_cnt": 123,
  "time": "2025-01-22T12:34:56Z"
}
```

## Log Analysis

### Uplink count (last 1 hour)

```bash
docker compose logs stack --since 1h 2>&1 | grep "Received uplink" | wc -l
```

### Join request count

```bash
docker compose logs stack --since 1h 2>&1 | grep "Join-request" | wc -l
```

### Devices with most errors

```bash
docker compose logs stack 2>&1 | grep -i error | grep -oP 'dev_eui=\K[A-F0-9]+' | sort | uniq -c | sort -rn | head
```

## Log Rotation

Logs are managed by Docker:

```yaml
# docker-compose.yml
services:
  stack:
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "3"
```

## Related Commands

- `/troubleshoot` - Log analysis for troubleshooting
- `/status` - System status

## Related Skill

- `@troubleshooting` - Log patterns and analysis
