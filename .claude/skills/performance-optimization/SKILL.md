# Performance Optimization Skill

## Overview

The Things Stack performans optimizasyonu, büyük ölçekli IoT deploymentları için kritiktir. Bu skill, Redis/PostgreSQL tuning, connection pooling, batch operations, caching strategies ve kaynak yönetimi konularını kapsar.

## Key Concepts

### Performance Bottlenecks

```
┌─────────────────────────────────────────────────────────────┐
│                   Common Bottlenecks                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Database I/O                                             │
│     ├── PostgreSQL query latency                            │
│     ├── Redis memory pressure                               │
│     └── Connection pool exhaustion                          │
│                                                              │
│  2. Network I/O                                              │
│     ├── gRPC connection overhead                            │
│     ├── Gateway connections (UDP/WS/MQTT)                   │
│     └── Integration webhooks                                │
│                                                              │
│  3. CPU                                                      │
│     ├── Encryption/decryption                               │
│     ├── MIC calculation                                     │
│     └── Payload encoding/decoding                           │
│                                                              │
│  4. Memory                                                   │
│     ├── Device state caching                                │
│     ├── Message queues                                      │
│     └── Connection buffers                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Scaling Strategies

| Component | Horizontal | Vertical | Notes |
|-----------|------------|----------|-------|
| Gateway Server | ✓ | ✓ | Gateway'ler farklı GS'lere bağlanabilir |
| Network Server | ✓ | ✓ | DevAddr routing gerektirir |
| Application Server | ✓ | ✓ | Stateless, kolayca scale edilir |
| Identity Server | △ | ✓ | PostgreSQL limitleri var |
| Join Server | ✓ | ✓ | Join request'ler dağıtılabilir |

## Redis Optimization

### Memory Configuration

```yaml
# redis.conf
maxmemory 4gb
maxmemory-policy allkeys-lru

# Hash optimization for small hashes
hash-max-ziplist-entries 512
hash-max-ziplist-value 64

# List optimization
list-max-ziplist-size -2
list-compress-depth 0

# Set optimization
set-max-intset-entries 512
```

### Connection Pooling

```yaml
# ttn-lw-stack.yml
redis:
  pool-size: 100              # Total connections
  min-idle-connections: 10    # Keep warm connections
  max-retries: 3
  read-timeout: 3s
  write-timeout: 3s
```

### Pipeline Usage

```go
// Batch operations reduce round trips
pipe := r.Pipeline()
for _, key := range keys {
    pipe.Get(ctx, key)
}
results, err := pipe.Exec(ctx)
```

### Key Design Patterns

```
# BAD: Long keys waste memory
ns:application:my-very-long-application-name:device:my-very-long-device-name

# GOOD: Use UIDs or hashes
ns:uid:{short-uid}

# BAD: Large values
ns:uid:{uid} → {huge JSON}

# GOOD: Hash fields
ns:uid:{uid}
├── ids
├── session
└── mac_state
```

### Monitoring Commands

```bash
# Real-time stats
redis-cli --stat

# Memory analysis
redis-cli INFO memory
redis-cli MEMORY STATS
redis-cli MEMORY DOCTOR

# Slow operations
redis-cli CONFIG SET slowlog-log-slower-than 10000
redis-cli SLOWLOG GET 10

# Key analysis
redis-cli --bigkeys
redis-cli DEBUG OBJECT key
```

## PostgreSQL Optimization

### Connection Pool Configuration

```yaml
is:
  database:
    max-open-connections: 100   # Max concurrent connections
    max-idle-connections: 10    # Keep idle connections warm
    conn-max-lifetime: 1h       # Recycle connections
```

### Index Recommendations

```sql
-- Frequently queried fields should have indexes
CREATE INDEX idx_end_devices_application_id ON end_devices(application_id);
CREATE INDEX idx_end_devices_dev_eui ON end_devices(dev_eui);
CREATE INDEX idx_gateways_gateway_eui ON gateways(gateway_eui);
CREATE INDEX idx_api_keys_entity_id ON api_keys(entity_id);
```

### Query Optimization

```sql
-- Enable query statistics
CREATE EXTENSION pg_stat_statements;

-- Find slow queries
SELECT query, calls, mean_time, total_time
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;

-- Analyze specific query
EXPLAIN ANALYZE SELECT * FROM end_devices WHERE application_id = 'my-app';
```

### Vacuum and Maintenance

```sql
-- Auto vacuum settings
ALTER TABLE end_devices SET (autovacuum_vacuum_scale_factor = 0.02);
ALTER TABLE end_devices SET (autovacuum_analyze_scale_factor = 0.01);

-- Manual maintenance
VACUUM ANALYZE end_devices;
REINDEX TABLE end_devices;
```

## Batch Operations

### Device Batch Operations

```bash
# Batch get devices
POST /applications/{app_id}/devices/batch
{
  "device_ids": ["device-1", "device-2", "device-3"]
}

# Batch delete devices
DELETE /applications/{app_id}/devices/batch
{
  "device_ids": ["device-1", "device-2"]
}
```

### Downlink Queue Batch

```go
// pkg/applicationserver/
// Use DownlinkQueueReplace instead of multiple Push calls
rpc DownlinkQueueReplace(DownlinkQueueRequest) returns (google.protobuf.Empty)
```

## Caching Strategies

### Device Registry Cache

```yaml
# Network Server caching
ns:
  device-registry:
    cache:
      enable: true
      ttl: 5m
      size: 10000
```

### Frequency Plan Cache

```go
// Frequency plans are cached in memory
// No configuration needed, automatic
```

### API Response Cache

```yaml
# HTTP caching headers
http:
  cache:
    enable: true
    max-age: 60
```

## Resource Limits

### Container Limits

```yaml
# docker-compose.yml
services:
  stack:
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '2'
          memory: 4G
```

### Go Runtime

```yaml
# Environment variables
GOMAXPROCS: 4
GOGC: 100  # Garbage collection percentage
```

### Rate Limiting

```yaml
rate-limiting:
  memory:
    max-per-second: 100
    burst-size: 20

  # Per-entity limits
  profiles:
    default:
      max-rate: 10
      associations: 1
```

## Common Tasks

### Task 1: Profile CPU Usage

```bash
# Enable pprof endpoint
http:
  pprof:
    enable: true
    password: "secret"

# Access profiles
curl http://localhost:1885/debug/pprof/profile?seconds=30 > cpu.prof
go tool pprof cpu.prof
```

### Task 2: Profile Memory

```bash
# Get heap profile
curl http://localhost:1885/debug/pprof/heap > heap.prof
go tool pprof heap.prof

# Get allocations
curl http://localhost:1885/debug/pprof/allocs > allocs.prof
```

### Task 3: Optimize High-Traffic Deployment

**1. Horizontal Scale**:
```yaml
# Run multiple instances
docker-compose up -d --scale stack=3
```

**2. Load Balancer**:
```nginx
upstream tts {
    least_conn;
    server stack-1:8885;
    server stack-2:8885;
    server stack-3:8885;
}
```

**3. Redis Cluster**:
```yaml
redis:
  cluster:
    addresses:
      - redis-1:6379
      - redis-2:6379
      - redis-3:6379
```

### Task 4: Monitor Performance Metrics

```yaml
# Enable Prometheus metrics
http:
  metrics:
    enable: true
    path: "/metrics"

# Key metrics to monitor
grpc_server_handling_seconds_bucket
redis_pool_stats_hits_total
pg_stat_activity_count
```

### Task 5: Tune for Low-Latency

```yaml
# Network Server
ns:
  deduplication-window: 100ms    # Reduce dedup window
  cooldown-window: 50ms

# Gateway Server
gs:
  udp:
    schedule-late-time: 500ms   # Reduce scheduling delay

# Application Server
as:
  webhooks:
    timeout: 5s
    queue-size: 1000
```

### Task 6: Optimize Webhook Performance

```yaml
as:
  webhooks:
    # Connection pool
    timeout: 10s
    max-concurrent: 100

    # Retry settings
    retry:
      enable: true
      max-attempts: 3
      initial-interval: 1s
      max-interval: 1h

    # Queue
    queue-size: 10000
```

## Code Patterns

### Efficient Device Lookup

```go
// BAD: Multiple lookups
for _, devAddr := range devAddrs {
    dev, _ := registry.GetByDevAddr(ctx, devAddr)
}

// GOOD: Batch lookup
devices, _ := registry.GetByDevAddrs(ctx, devAddrs)
```

### Connection Reuse

```go
// BAD: New connection per request
for _, req := range requests {
    conn, _ := grpc.Dial(target)
    defer conn.Close()
}

// GOOD: Connection pool
pool := grpcpool.New(target, poolSize)
for _, req := range requests {
    conn := pool.Get()
    // use conn
    pool.Put(conn)
}
```

### Event Batching

```go
// BAD: Publish events one by one
for _, event := range events {
    pubsub.Publish(ctx, event)
}

// GOOD: Batch publish
pubsub.PublishBatch(ctx, events)
```

## Configuration Reference

### Production Configuration

```yaml
# ttn-lw-stack.yml (production optimized)

# HTTP
http:
  listen: ":1885"
  listen-tls: ":8885"

# gRPC
grpc:
  listen: ":1884"
  listen-tls: ":8884"

# Redis
redis:
  address: "redis:6379"
  pool-size: 100
  min-idle-connections: 20
  read-timeout: 1s
  write-timeout: 1s

# PostgreSQL
is:
  database-uri: "postgres://..."
  database:
    max-open-connections: 100
    max-idle-connections: 25
    conn-max-lifetime: 30m

# Network Server
ns:
  deduplication-window: 200ms
  cooldown-window: 100ms

# Gateway Server
gs:
  udp:
    schedule-late-time: 800ms
    connection-error-limit: 100
    rate-limiting:
      enable: true
      messages: 20
      messages-size: 20000

# Logging (reduce in production)
log:
  level: warn
  format: json
```

## File References

| Kategori | Dosya |
|----------|-------|
| Redis Config | Component `redis` sections |
| PostgreSQL Config | `is.database-uri`, `is.database` |
| Rate Limiting | `rate-limiting` section |
| Metrics | `http.metrics` section |
| NS Performance | `pkg/networkserver/config.go` |
| AS Performance | `pkg/applicationserver/config.go` |
| GS Performance | `pkg/gatewayserver/config.go` |

## Troubleshooting

### High CPU Usage
- pprof ile profile al
- Encryption/MIC calculation overhead olabilir
- Log level'ı azalt

### High Memory Usage
- Redis maxmemory kontrol et
- Go heap profile al
- Connection buffer'ları kontrol et

### Slow API Response
- Database query'leri optimize et
- Connection pool boyutunu artır
- Cache enable et

### Message Delays
- Deduplication window'u kontrol et
- Gateway'den GS'ye latency
- Redis round-trip time

### Rate Limiting Triggered
- Rate limit threshold'larını artır
- Burst size'ı artır
- Traffic pattern'ı analiz et
