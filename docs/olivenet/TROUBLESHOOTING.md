# The Things Stack - Troubleshooting Guide (Olivenet)

## Overview

This guide covers common issues and solutions for Olivenet's The Things Stack deployment.

## Quick Diagnostics

### System Health Check

```bash
# Check all services
docker-compose ps

# Check logs (last 100 lines)
docker-compose logs --tail=100 stack

# Check resource usage
docker stats

# Test database connections
docker-compose exec stack ttn-lw-stack is-db check
docker-compose exec redis redis-cli PING
```

### Component Status

```bash
# Health endpoint
curl http://localhost:1885/healthz

# Readiness endpoint
curl http://localhost:1885/readyz

# Metrics (Prometheus format)
curl http://localhost:1885/metrics | grep -E "^(gs_|ns_|as_)"
```

---

## Gateway Issues

### Gateway Not Connecting

**Symptoms**: Gateway shows offline in Console, no uplinks received.

**Diagnostics**:
```bash
# Check UDP port accessibility
nc -vzu lorawan.olivenet.com 1700

# Check gateway logs on stack
docker-compose logs stack 2>&1 | grep -i "gateway"

# Verify gateway registration
ttn-lw-cli gateways get my-gateway --all
```

**Common Causes & Solutions**:

| Cause | Solution |
|-------|----------|
| Firewall blocking UDP 1700 | Open UDP 1700 inbound |
| Gateway EUI mismatch | Verify EUI in gateway config matches TTS |
| Gateway not registered | Register gateway via CLI or Console |
| Clock sync issue | Ensure gateway NTP is configured |

**Gateway Configuration Check**:
```bash
# UDP Packet Forwarder (global_conf.json)
{
  "gateway_conf": {
    "server_address": "lorawan.olivenet.com",
    "serv_port_up": 1700,
    "serv_port_down": 1700
  }
}
```

### Gateway Connected but No Uplinks

**Diagnostics**:
```bash
# Check gateway traffic
docker-compose logs stack 2>&1 | grep "gs:" | tail -50

# Verify frequency plan
ttn-lw-cli gateways get my-gateway --frequency-plan-id
```

**Solutions**:
- Verify frequency plan matches gateway region (EU_863_870 for Cyprus)
- Check gateway antenna connection
- Verify device is transmitting (use LoRa sniffer if available)

---

## Device Issues

### Device Not Joining (OTAA)

**Symptoms**: Join requests sent but no Join Accept received.

**Diagnostics**:
```bash
# Check join requests in logs
docker-compose logs stack 2>&1 | grep -i "join"

# Verify device registration
ttn-lw-cli end-devices get energy-meters meter-001 --all

# Check event stream
ttn-lw-cli events subscribe --device-id meter-001 --application-id energy-meters
```

**Common Causes & Solutions**:

| Symptom | Cause | Solution |
|---------|-------|----------|
| "MIC mismatch" | Wrong AppKey | Verify AppKey matches device |
| "DevNonce already used" | Device reused nonce | Reset device or clear DevNonce list |
| "Unknown device" | Device not registered | Register device with correct EUIs |
| No join request seen | Gateway issue | See Gateway troubleshooting |

**Reset DevNonce List**:
```bash
ttn-lw-cli end-devices reset energy-meters meter-001 --session
```

### Uplinks Not Appearing

**Diagnostics**:
```bash
# Check NS processing
docker-compose logs stack 2>&1 | grep "ns:" | grep "meter-001"

# Check frame counters
ttn-lw-cli end-devices get energy-meters meter-001 --session.last-f-cnt-up

# Verify device session
ttn-lw-cli end-devices get energy-meters meter-001 --session
```

**Common Causes**:
- Frame counter reset (device rebooted without session persistence)
- MIC verification failing (session key mismatch)
- Device sending on wrong frequency

**Solution for Frame Counter Issues**:
```bash
# Option 1: Reset session (device must rejoin)
ttn-lw-cli end-devices reset energy-meters meter-001

# Option 2: Disable frame counter check (NOT RECOMMENDED for production)
ttn-lw-cli end-devices set energy-meters meter-001 \
  --mac-settings.resets-f-cnt true
```

### Downlinks Not Delivered

**Diagnostics**:
```bash
# Check downlink queue
ttn-lw-cli end-devices downlink list energy-meters meter-001

# Check scheduled downlinks
docker-compose logs stack 2>&1 | grep "downlink"
```

**Common Causes**:
- No Class A receive window (device must send uplink first)
- Gateway transmit issue
- Duty cycle exhausted

---

## Webhook Issues

### Webhooks Failing

**Diagnostics**:
```bash
# Check webhook status
ttn-lw-cli applications webhooks get energy-meters thingsboard-telemetry

# Check AS logs
docker-compose logs stack 2>&1 | grep "webhook"

# Test endpoint manually
curl -X POST https://thingsboard.olivenet.com/api/v1/test/telemetry \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
```

**Common Causes & Solutions**:

| Error | Cause | Solution |
|-------|-------|----------|
| Connection refused | Target server down | Verify ThingsBoard is running |
| 401 Unauthorized | Auth issue | Check API tokens |
| 504 Gateway Timeout | Slow response | Increase timeout in webhook config |
| Certificate error | TLS issue | Verify certificates |

**Webhook Retry Configuration**:
```yaml
# In ttn-lw-stack.yml
as:
  webhooks:
    retry:
      enabled: true
      max-attempts: 5
      interval: 1m
```

### Webhook Latency

**Diagnostics**:
```bash
# Check webhook queue depth
curl http://localhost:1885/metrics | grep "as_webhook_queue"

# Check worker count
docker-compose logs stack 2>&1 | grep "webhook worker"
```

**Solution - Increase Workers**:
```yaml
as:
  webhooks:
    queue-size: 2000
    workers: 32
```

---

## Database Issues

### PostgreSQL Connection Failed

**Symptoms**: "connection refused" or "timeout" errors.

**Diagnostics**:
```bash
# Check PostgreSQL status
docker-compose exec postgres pg_isready -U ttn

# Check connections
docker-compose exec postgres psql -U ttn -c "SELECT count(*) FROM pg_stat_activity;"

# Check disk space
docker-compose exec postgres df -h /var/lib/postgresql/data
```

**Solutions**:
```bash
# Restart PostgreSQL
docker-compose restart postgres

# If out of connections, increase limit
# In docker-compose.yml:
postgres:
  command: postgres -c max_connections=300
```

### Redis Memory Issues

**Diagnostics**:
```bash
# Check memory usage
docker-compose exec redis redis-cli INFO memory

# Check key count
docker-compose exec redis redis-cli DBSIZE

# Find large keys
docker-compose exec redis redis-cli --bigkeys
```

**Solutions**:
```bash
# Clear specific cache (e.g., deduplication)
docker-compose exec redis redis-cli KEYS "ttn:v3:dedup:*" | xargs redis-cli DEL

# Increase memory limit (docker-compose.yml)
redis:
  command: redis-server --maxmemory 1gb --maxmemory-policy allkeys-lru
```

---

## TLS/Certificate Issues

### Certificate Expired

**Diagnostics**:
```bash
# Check certificate expiry
echo | openssl s_client -connect lorawan.olivenet.com:443 2>/dev/null | \
  openssl x509 -noout -dates

# Check ACME status
docker-compose logs stack 2>&1 | grep -i "acme\|certificate"
```

**Solutions**:

For ACME (Let's Encrypt):
```bash
# Certificates auto-renew, but if stuck:
docker-compose restart stack

# Check ACME directory permissions
ls -la /var/lib/acme/
```

For file-based certificates:
```bash
# Replace certificates
cp new-cert.pem deploy/olivenet/certs/cert.pem
cp new-key.pem deploy/olivenet/certs/key.pem
docker-compose restart stack
```

### Certificate Mismatch

**Symptoms**: "certificate verify failed" errors.

**Solution**:
```bash
# Verify certificate chain
openssl verify -CAfile ca.pem cert.pem

# Check certificate matches key
openssl x509 -noout -modulus -in cert.pem | md5sum
openssl rsa -noout -modulus -in key.pem | md5sum
# Both should match
```

---

## Performance Issues

### High CPU Usage

**Diagnostics**:
```bash
# Check CPU by component
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Profile Go application
curl http://localhost:1885/debug/pprof/profile?seconds=30 > cpu.prof
go tool pprof cpu.prof
```

**Common Causes**:
- Too many concurrent gateway connections
- Excessive webhook retries
- Inefficient payload formatters

### High Memory Usage

**Diagnostics**:
```bash
# Check memory
curl http://localhost:1885/debug/pprof/heap > heap.prof
go tool pprof heap.prof

# Check goroutine count
curl http://localhost:1885/metrics | grep go_goroutines
```

**Solutions**:
- Increase container memory limit
- Review payload formatter for memory leaks
- Tune Redis cache size

### Slow Response Times

**Diagnostics**:
```bash
# Check API latency
time curl -s https://lorawan.olivenet.com/api/v3/applications/energy-meters

# Check database query times
docker-compose exec postgres psql -U ttn -c "
SELECT query, calls, mean_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;"
```

---

## Log Analysis

### Enable Debug Logging

```yaml
# In ttn-lw-stack.yml
log:
  level: debug

# Or via environment
TTN_LW_LOG_LEVEL=debug
```

### Filter Logs by Component

```bash
# Gateway Server logs
docker-compose logs stack 2>&1 | grep "gs:"

# Network Server logs
docker-compose logs stack 2>&1 | grep "ns:"

# Application Server logs
docker-compose logs stack 2>&1 | grep "as:"

# Specific device
docker-compose logs stack 2>&1 | grep "dev_eui=0102030405060708"
```

### JSON Log Parsing

```bash
# Parse structured logs with jq
docker-compose logs stack 2>&1 | \
  grep -E "^\{" | \
  jq 'select(.namespace == "networkserver" and .level == "error")'
```

---

## Emergency Procedures

### Complete System Recovery

```bash
# Stop all services
docker-compose down

# Backup current state
docker-compose exec postgres pg_dump -U ttn ttn_lorawan > backup.sql
docker cp olivenet_redis_1:/data/dump.rdb backup.rdb

# Clear all data (DESTRUCTIVE)
docker volume rm olivenet_postgres_data olivenet_redis_data

# Restore from backup
docker-compose up -d postgres redis
docker-compose exec -T postgres psql -U ttn ttn_lorawan < backup.sql
docker cp backup.rdb olivenet_redis_1:/data/dump.rdb
docker-compose restart redis

# Start stack
docker-compose up -d stack
```

### Gateway Mass Disconnect Recovery

```bash
# Check gateway connection limits
curl http://localhost:1885/metrics | grep gs_connected

# Restart Gateway Server component only
docker-compose exec stack ttn-lw-stack gs restart
```

---

## Contact & Escalation

### Useful Log Locations

```
/var/log/docker/              # Docker daemon logs
deploy/olivenet/logs/         # Application logs (if configured)
```

### Support Resources

- **GitHub Issues**: https://github.com/TheThingsNetwork/lorawan-stack/issues
- **Documentation**: https://www.thethingsindustries.com/docs/
- **Community Forum**: https://www.thethingsnetwork.org/forum/

### Information to Collect for Support

```bash
# System info
uname -a
docker --version
docker-compose --version

# Stack version
docker-compose exec stack ttn-lw-stack version

# Recent logs
docker-compose logs --tail=500 stack > stack-logs.txt

# Configuration (remove secrets)
cat deploy/olivenet/config/ttn-lw-stack.yml | grep -v password > config-sanitized.yml
```
