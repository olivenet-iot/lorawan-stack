# Troubleshooting Skill

## Overview

The Things Stack troubleshooting requires debugging at various levels: gateway connectivity, device communication, integration failures, and system health. This skill covers common issues, log analysis, and debug procedures.

## Key Concepts

### Diagnostic Flow

```
┌─────────────────────────────────────────────────────────────┐
│                   Diagnostic Flow                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Gateway Issues                                           │
│     ├── Connection status                                   │
│     ├── Protocol errors                                     │
│     └── Network/firewall                                    │
│                                                              │
│  2. Device Issues                                            │
│     ├── Join failures                                       │
│     ├── Uplink problems                                     │
│     └── Downlink failures                                   │
│                                                              │
│  3. Integration Issues                                       │
│     ├── Webhook failures                                    │
│     ├── MQTT connectivity                                   │
│     └── Data format errors                                  │
│                                                              │
│  4. System Issues                                            │
│     ├── Component health                                    │
│     ├── Database connectivity                               │
│     └── Resource exhaustion                                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Event Names Reference

| Component | Event Pattern | Description |
|-----------|--------------|-------------|
| GS | `gs.up.receive` | Gateway uplink received |
| GS | `gs.down.send` | Gateway downlink sent |
| GS | `gs.status.receive` | Gateway status |
| GS | `gs.gateway.connect` | Gateway connected |
| GS | `gs.gateway.disconnect` | Gateway disconnected |
| NS | `ns.up.receive` | NS received uplink |
| NS | `ns.up.forward` | NS forwarded to AS |
| NS | `ns.up.drop` | NS dropped uplink |
| NS | `ns.down.schedule` | NS scheduled downlink |
| NS | `ns.mac.xxx` | MAC command events |
| AS | `as.up.receive` | AS received uplink |
| AS | `as.up.forward.xxx` | AS forwarded to integration |
| AS | `as.down.push` | Downlink queued |
| JS | `js.join.accept` | Join accepted |
| JS | `js.join.reject` | Join rejected |

### Log Levels

```yaml
log:
  level: debug  # debug, info, warn, error
  format: json  # json, console
```

## Gateway Troubleshooting

### Gateway Not Connecting

**Symptoms**: Gateway doesn't appear in console, no status updates

**Check List**:
```bash
# 1. Check gateway status in API
curl -H "Authorization: Bearer $API_KEY" \
  "https://example.com/api/v3/gs/gateways/my-gateway/connection/stats"

# 2. Check gateway server logs
docker-compose logs -f stack | grep -i gateway

# 3. Verify network connectivity
# UDP (Packet Forwarder)
nc -uvz example.com 1700

# WebSocket (BasicStation)
curl -I https://example.com:8887

# 4. Check firewall
sudo iptables -L -n | grep 1700
```

**UDP Packet Forwarder Issues**:
```bash
# Gateway config (global_conf.json)
{
  "gateway_conf": {
    "gateway_ID": "B827EBFFFE123456",  # Must match registration
    "server_address": "example.com",
    "serv_port_up": 1700,
    "serv_port_down": 1700
  }
}

# Common issues:
# - Gateway EUI mismatch
# - Wrong server address/port
# - Firewall blocking UDP
```

**BasicStation Issues**:
```bash
# tc.uri file
wss://example.com:8887

# tc.key file (API Key)
Authorization: Bearer NNSXS.XXX...

# Common issues:
# - Invalid TLS certificate
# - API key expired or wrong rights
# - Port blocked
```

### Gateway Disconnecting Frequently

**Symptoms**: Gateway connects but disconnects after short time

**Check**:
```bash
# Look for disconnect reasons in events
GET /events?names=gs.gateway.disconnect&identifiers.gateway_ids.gateway_id=my-gateway

# Check keepalive
# UDP: stat_interval in global_conf.json (default 30s)
# BasicStation: automatic heartbeat
```

**Common Causes**:
- Network instability
- Firewall timeout (UDP NAT)
- Duplicate gateway ID
- Server-side error

## Device Troubleshooting

### Join Request Failing

**Symptoms**: Device tries to join but never succeeds

**Debug Steps**:
```bash
# 1. Check join events
GET /events?names=js.join.*&identifiers.device_ids.application_ids.application_id=my-app&identifiers.device_ids.device_id=my-device

# 2. Common events:
# js.join.accept - Join successful
# js.join.reject.xxx - Join rejected with reason

# 3. Check device registration
GET /js/applications/my-app/devices/my-device
```

**Common Issues**:

| Error | Cause | Solution |
|-------|-------|----------|
| MIC mismatch | Wrong AppKey | Verify AppKey |
| DevNonce reused | Replay protection | Reset device |
| Unknown device | Not registered in JS | Register in JS |
| EUI mismatch | Wrong DevEUI/JoinEUI | Verify EUIs |

### Uplink Not Received

**Symptoms**: Device sends data but nothing appears in console

**Debug Steps**:
```bash
# 1. Check if gateway received
GET /events?names=gs.up.receive&identifiers.gateway_ids.gateway_id=my-gateway

# 2. Check if NS received
GET /events?names=ns.up.receive&identifiers.device_ids.application_ids.application_id=my-app

# 3. Check if dropped
GET /events?names=ns.up.drop.*

# 4. Check device session
GET /ns/applications/my-app/devices/my-device?field_mask=session,mac_state
```

**Common Issues**:

| Issue | Event | Solution |
|-------|-------|----------|
| Gateway not connected | No gs.up.receive | Fix gateway |
| Wrong DevAddr | ns.up.drop.unknown_dev_addr | Check ABP config |
| MIC failure | ns.up.drop.invalid_mic | Check keys |
| Frame counter | ns.up.drop.invalid_f_cnt | Reset counters |

### Downlink Not Received

**Symptoms**: Downlinks queued but device doesn't receive

**Debug Steps**:
```bash
# 1. Check downlink queue
GET /as/applications/my-app/devices/my-device/down

# 2. Check NS scheduled
GET /events?names=ns.down.schedule*

# 3. Check GS sent
GET /events?names=gs.down.send*

# 4. Check TX acknowledgment
GET /events?names=gs.down.tx.*
```

**Common Issues**:

| Issue | Cause | Solution |
|-------|-------|----------|
| Queue not draining | Class A, no uplinks | Wait for uplink |
| Duty cycle | Limit exceeded | Wait or use different channel |
| No gateway | Gateway disconnected | Fix gateway |
| RX window missed | Timing issue | Check RX delay config |

### Frame Counter Mismatch

**Symptoms**: "invalid frame counter" errors

**Solution**:
```bash
# For ABP devices:
# Option 1: Reset counter on device and server
PUT /ns/applications/my-app/devices/my-device
{
  "end_device": {
    "session": {
      "last_f_cnt_up": 0
    }
  },
  "field_mask": {"paths": ["session.last_f_cnt_up"]}
}

# Option 2: Enable frame counter reset
PUT /ns/applications/my-app/devices/my-device
{
  "end_device": {
    "mac_settings": {
      "resets_f_cnt": true
    }
  },
  "field_mask": {"paths": ["mac_settings.resets_f_cnt"]}
}
```

## Integration Troubleshooting

### Webhook Not Receiving Data

**Debug Steps**:
```bash
# 1. Check webhook configuration
GET /as/applications/my-app/webhooks/my-webhook

# 2. Check webhook events
GET /events?names=as.up.forward.webhook*

# 3. Check for errors
GET /events?names=as.webhook.fail*

# 4. Test webhook endpoint
curl -X POST -H "Content-Type: application/json" \
  -d '{"test": true}' \
  https://my-webhook-endpoint.com/data
```

**Common Issues**:

| Issue | Solution |
|-------|----------|
| 4xx response | Check endpoint auth |
| 5xx response | Endpoint server error |
| Timeout | Increase timeout or fix endpoint |
| TLS error | Fix certificate |
| DNS error | Check endpoint URL |

### MQTT Connection Issues

**Debug Steps**:
```bash
# 1. Check connection info
GET /as/applications/my-app/mqtt-connection-info

# 2. Test connection
mosquitto_sub -h example.com -p 8883 \
  -u "my-app@tenant" -P "$API_KEY" \
  -t "v3/my-app@tenant/devices/+/up" \
  --cafile ca.pem

# 3. Check events
GET /events?names=as.up.forward.mqtt*
```

**Common Issues**:

| Issue | Solution |
|-------|----------|
| Auth failed | Check username format and API key |
| TLS error | Use correct port (8883 for TLS) |
| Topic wrong | Use correct topic format |
| Connection refused | Check firewall, server status |

## System Troubleshooting

### Component Health Check

```bash
# HTTP health endpoint
curl http://localhost:1885/healthz

# Per-component status
docker-compose ps

# Component logs
docker-compose logs -f stack | grep -E "(error|ERROR|panic)"
```

### Database Connectivity

**PostgreSQL**:
```bash
# Test connection
docker-compose exec postgres pg_isready -U ttn

# Check connections
docker-compose exec postgres psql -U ttn -c "SELECT count(*) FROM pg_stat_activity;"

# Check for locks
docker-compose exec postgres psql -U ttn -c "SELECT * FROM pg_locks WHERE NOT granted;"
```

**Redis**:
```bash
# Test connection
docker-compose exec redis redis-cli PING

# Memory status
docker-compose exec redis redis-cli INFO memory

# Check connections
docker-compose exec redis redis-cli CLIENT LIST
```

### Resource Issues

**Memory**:
```bash
# Check container memory
docker stats

# Check host memory
free -h

# Redis memory
docker-compose exec redis redis-cli INFO memory | grep used_memory_human
```

**Disk**:
```bash
# Check disk usage
df -h

# Check Docker volumes
docker system df

# Clean up
docker system prune -a
```

**CPU**:
```bash
# Check CPU usage
top -p $(pgrep -d, ttn-lw-stack)

# Check container CPU
docker stats --no-stream
```

## Log Analysis

### Log Patterns

```bash
# Gateway connection issues
grep -i "gateway.*connect" logs.txt

# Join failures
grep -i "join.*reject\|join.*fail" logs.txt

# Uplink drops
grep -i "up.*drop\|uplink.*drop" logs.txt

# MIC failures
grep -i "mic\|invalid.*mic" logs.txt

# Frame counter issues
grep -i "f_cnt\|frame.*counter" logs.txt

# Database errors
grep -i "database\|postgres\|redis" logs.txt
```

### Log Correlation

```bash
# Find all logs for a specific device
grep "my-device-id" logs.txt

# Find all logs for a correlation ID
grep "correlation_id=xyz" logs.txt

# Trace uplink through all components
grep "correlation_id=xyz" logs.txt | grep -E "(gs|ns|as)"
```

### Structured Log Query (JSON)

```bash
# Using jq for JSON logs
cat logs.json | jq 'select(.level == "error")'
cat logs.json | jq 'select(.device_id == "my-device")'
cat logs.json | jq 'select(.event | startswith("ns.up"))'
```

## Common Tasks

### Task 1: Trace End-to-End Uplink

```bash
# 1. Find uplink in gateway server
GET /events?names=gs.up.receive&after=2025-01-20T10:00:00Z

# 2. Get correlation_id from response
# "correlation_id": "abc123"

# 3. Trace through all components
GET /events?correlation_id=abc123

# 4. Check for drops or errors
# Look for ns.up.drop.* or error events
```

### Task 2: Debug Specific Device

```bash
# All events for a device
GET /events?identifiers.device_ids.application_ids.application_id=my-app&identifiers.device_ids.device_id=my-device

# Device state
GET /applications/my-app/devices/my-device?field_mask=session,mac_state,pending_session

# Recent uplinks
GET /events?names=ns.up.receive&identifiers.device_ids.device_id=my-device
```

### Task 3: Gateway Connectivity Test

```bash
# Connection stats
GET /gs/gateways/my-gateway/connection/stats

# Recent status messages
GET /events?names=gs.status.receive&identifiers.gateway_ids.gateway_id=my-gateway

# Recent uplinks through gateway
GET /events?names=gs.up.receive&identifiers.gateway_ids.gateway_id=my-gateway
```

### Task 4: Reset Device State

```bash
# 1. Delete from NS (clears session)
DELETE /ns/applications/my-app/devices/my-device

# 2. Re-register in NS
PUT /ns/applications/my-app/devices/my-device
{
  "end_device": {...},
  "field_mask": {...}
}

# For OTAA: Device will rejoin
# For ABP: Need to re-provision session keys
```

## Diagnostic Commands Reference

### ttn-lw-cli Commands

```bash
# Device info
ttn-lw-cli end-devices get my-app my-device

# Gateway info
ttn-lw-cli gateways get my-gateway

# Application info
ttn-lw-cli applications get my-app

# Events stream
ttn-lw-cli events subscribe --application-id my-app
```

### curl Commands

```bash
# Health check
curl http://localhost:1885/healthz

# Get device
curl -H "Authorization: Bearer $KEY" \
  "https://example.com/api/v3/applications/my-app/devices/my-device"

# Stream events
curl -N -H "Authorization: Bearer $KEY" \
  "https://example.com/api/v3/events?names=gs.up.receive"
```

## File References

| Category | File |
|----------|------|
| Events Proto | `api/ttn/lorawan/v3/events.proto` |
| Error Definitions | `pkg/errors/` |
| NS Error Handling | `pkg/networkserver/mac/errors.go` |
| GS Connection | `pkg/gatewayserver/io/` |
| Uplink Handler | `pkg/networkserver/grpc_gsns.go` |
| AS Integration | `pkg/applicationserver/io/` |

## Quick Reference

### Error Code Meanings

| Code | Meaning |
|------|---------|
| 3 (InvalidArgument) | Invalid request data |
| 5 (NotFound) | Entity not found |
| 7 (PermissionDenied) | Insufficient rights |
| 16 (Unauthenticated) | Missing/invalid auth |

### Event Data Fields

| Field | Description |
|-------|-------------|
| correlation_id | Trace ID across components |
| identifiers | Entity identifiers |
| data | Event-specific payload |
| time | Event timestamp |
| origin | Source component |
