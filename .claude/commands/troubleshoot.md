# /troubleshoot Command

Troubleshooting guide and diagnostics.

## Parameters

| Parameter | Description |
|-----------|-------------|
| gateway | Gateway connection issues |
| device | Device issues (join, uplink) |
| join | Join failure analysis |
| uplink | Uplink issues |
| downlink | Downlink issues |
| webhook | Webhook issues |
| performance | Performance issues |

## General Diagnostics

First run general status check:

```bash
cd /opt/lorawan-stack/deploy/olivenet/scripts
./health-check.sh
```

## Gateway Issues

### Gateway not connecting

1. Is port 1700 open?
```bash
ss -ulnp | grep 1700
nc -uvz localhost 1700
```

2. Gateway Server logs:
```bash
docker compose logs stack 2>&1 | grep "gs:" | tail -50
```

3. Firewall check:
```bash
sudo ufw status
sudo iptables -L -n | grep 1700
```

4. Is Gateway EUI correct?
```bash
# Check from Console or CLI
ttn-lw-cli gateways get <gateway-id>
```

### Gateway connected but no traffic

1. Is frequency plan compatible?
2. Is gateway location set?
3. Is antenna connected? (physical)

## Join Issues

### Join request not visible

1. Is gateway connected?
2. Is device frequency plan correct?
3. Can device send uplink?

### Join accept not received

1. Is AppKey correct?
```bash
# Check from Console
ttn-lw-cli end-devices get <app-id> <dev-id> --root-keys
```

2. DevNonce replay?
```bash
docker compose logs stack 2>&1 | grep "Join-request" | grep <dev_eui>
```

3. Join Server logs:
```bash
docker compose logs stack 2>&1 | grep "js:" | tail -50
```

## Uplink Issues

### Uplink not visible

1. Is device session active?
2. Did frame counter reset?
3. MIC verification failure?

```bash
docker compose logs stack 2>&1 | grep <dev_eui> | tail -50
```

### Uplink received but not reaching Application Server

1. Is device routing correct?
2. Application Server logs:
```bash
docker compose logs stack 2>&1 | grep "as:" | tail -50
```

## Downlink Issues

### Downlink not being sent

1. Class A device - is it after uplink?
2. Does gateway support downlink?
3. Duty cycle limit exceeded?

```bash
docker compose logs stack 2>&1 | grep "Scheduling downlink" | tail -20
```

## Webhook Issues

### Webhook not being called

1. Is webhook URL correct?
2. Is TLS certificate valid?
3. Timeout occurring?

```bash
docker compose logs stack 2>&1 | grep "webhook" | tail -50
```

### Webhook 4xx/5xx

1. Is endpoint reachable?
```bash
curl -v <webhook-url>
```

2. Is format correct?
3. Are authentication headers correct?

## Performance Issues

### High latency

1. Resource usage:
```bash
docker stats
```

2. PostgreSQL connection count:
```bash
docker compose exec postgres psql -U ttn -c "SELECT count(*) FROM pg_stat_activity;"
```

3. Redis memory:
```bash
docker compose exec redis redis-cli INFO memory
```

### High CPU/Memory

1. Check container limits:
```bash
docker compose config | grep -A5 deploy
```

2. Too much log volume?
3. Event backlog?

## Diagnostic Commands Summary

```bash
# General status
./health-check.sh

# Container logs
docker compose logs -f stack

# PostgreSQL connections
docker compose exec postgres psql -U ttn -c "SELECT count(*) FROM pg_stat_activity;"

# Redis status
docker compose exec redis redis-cli INFO

# Network check
ss -tlnp | grep -E "1700|1885|1884"

# Disk usage
df -h
du -sh /var/lib/docker
```

## Related Skill

For detailed troubleshooting:
- `@troubleshooting` - Comprehensive troubleshooting guide

## Related Commands

- `/logs` - Log viewing
- `/status` - System status
- `/test` - Connection tests
