# The Things Stack - Deployment Guide (Olivenet)

## Overview

This guide covers production deployment of The Things Stack for Olivenet's 3000+ energy meter infrastructure.

## Prerequisites

### Hardware Requirements
| Component | Minimum | Recommended (3000+ devices) |
|-----------|---------|----------------------------|
| CPU | 2 vCPU | 4 vCPU |
| RAM | 4 GB | 8 GB |
| Storage | 50 GB SSD | 100 GB SSD |
| Network | 50 Mbps | 100 Mbps |

### Software Requirements
- Docker 20.10+
- Docker Compose 2.0+
- Domain with DNS access
- TLS certificates (or Let's Encrypt)

## Quick Start

### 1. Clone and Configure

```bash
cd /path/to/lorawan-stack
cp deploy/olivenet/.env.example deploy/olivenet/.env
```

### 2. Edit Environment Variables

```bash
vim deploy/olivenet/.env

# Required changes:
# - DOMAIN=your-domain.com
# - POSTGRES_PASSWORD=<strong-password>
# - REDIS_PASSWORD=<strong-password>
# - ADMIN_PASSWORD=<strong-password>
# - CONSOLE_SECRET=<32-char-secret>
# - DEVICE_CLAIMING_SECRET=<32-char-secret>
```

### 3. Generate TLS Certificates

**Option A: Let's Encrypt (Recommended)**
```bash
# Certificates will be auto-generated on first start
# Ensure ports 80 and 443 are accessible from internet
```

**Option B: Custom Certificates**
```bash
mkdir -p deploy/olivenet/certs
cp your-cert.pem deploy/olivenet/certs/cert.pem
cp your-key.pem deploy/olivenet/certs/key.pem
cp your-ca.pem deploy/olivenet/certs/ca.pem
```

### 4. Start Services

```bash
cd deploy/olivenet
docker-compose up -d

# Check logs
docker-compose logs -f stack
```

### 5. Initialize Database

```bash
# Create admin user
docker-compose exec stack ttn-lw-stack is-db migrate
docker-compose exec stack ttn-lw-stack is-db create-admin-user \
  --id admin \
  --email admin@olivenet.com
```

## Production Configuration

### Docker Compose Structure

```
deploy/olivenet/
├── docker-compose.yml      # Production stack
├── docker-compose.dev.yml  # Development override
├── .env                    # Environment variables (not in git)
├── .env.example            # Template
├── certs/                  # TLS certificates
│   ├── cert.pem
│   ├── key.pem
│   └── ca.pem
└── config/
    └── ttn-lw-stack.yml    # Stack configuration
```

### Network Architecture

```
                    Internet
                        │
                        ▼
              ┌─────────────────┐
              │  Load Balancer  │
              │   (Optional)    │
              └────────┬────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
   ┌─────────┐   ┌─────────┐   ┌─────────┐
   │  :443   │   │ :1700   │   │ :8887   │
   │ HTTPS   │   │  UDP    │   │  WSS    │
   │ Console │   │ Gateway │   │BasicStn │
   └────┬────┘   └────┬────┘   └────┬────┘
        │              │              │
        └──────────────┼──────────────┘
                       │
              ┌────────▼────────┐
              │   TTS Stack     │
              │   Container     │
              └────────┬────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
    ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
    │PostgreSQL│   │  Redis  │   │  Blob   │
    │  :5432   │   │  :6379  │   │ Storage │
    └─────────┘   └─────────┘   └─────────┘
```

### Port Configuration

| Port | Protocol | Service | Firewall |
|------|----------|---------|----------|
| 80 | HTTP | ACME challenge | Open |
| 443 | HTTPS | Console/API | Open |
| 1700 | UDP | Packet Forwarder | Open |
| 8883 | MQTTS | MQTT | Open (if needed) |
| 8887 | WSS | BasicStation | Open |
| 5432 | TCP | PostgreSQL | Internal only |
| 6379 | TCP | Redis | Internal only |

## Database Configuration

### PostgreSQL Setup

```yaml
# Production settings
postgres:
  image: postgres:14
  environment:
    POSTGRES_USER: ttn
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    POSTGRES_DB: ttn_lorawan
  volumes:
    - postgres_data:/var/lib/postgresql/data
  command:
    - "postgres"
    - "-c"
    - "max_connections=200"
    - "-c"
    - "shared_buffers=256MB"
    - "-c"
    - "effective_cache_size=768MB"
```

### Redis Setup

```yaml
# Production settings
redis:
  image: redis:7
  command: >
    redis-server
    --appendonly yes
    --requirepass ${REDIS_PASSWORD}
    --maxmemory 512mb
    --maxmemory-policy allkeys-lru
  volumes:
    - redis_data:/data
```

## TLS Configuration

### Let's Encrypt (ACME)

```yaml
# config/ttn-lw-stack.yml
tls:
  source: acme
  acme:
    email: admin@olivenet.com
    hosts:
      - lorawan.olivenet.com
    default-host: lorawan.olivenet.com
    dir: /var/lib/acme
```

### Custom Certificates

```yaml
# config/ttn-lw-stack.yml
tls:
  source: file
  root-ca: /run/secrets/ca.pem
  certificate: /run/secrets/cert.pem
  key: /run/secrets/key.pem
```

## Backup Strategy

### Database Backup

```bash
#!/bin/bash
# backup.sh - Run daily via cron

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=/backups

# PostgreSQL
docker-compose exec -T postgres pg_dump -U ttn ttn_lorawan | \
  gzip > ${BACKUP_DIR}/postgres_${DATE}.sql.gz

# Redis
docker-compose exec -T redis redis-cli -a ${REDIS_PASSWORD} BGSAVE
docker cp olivenet_redis_1:/data/dump.rdb ${BACKUP_DIR}/redis_${DATE}.rdb

# Retain 30 days
find ${BACKUP_DIR} -type f -mtime +30 -delete
```

### Backup Schedule

```cron
# /etc/cron.d/tts-backup
0 2 * * * root /opt/tts/backup.sh >> /var/log/tts-backup.log 2>&1
```

## Monitoring

### Health Checks

```yaml
# docker-compose.yml
stack:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:1885/healthz"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 60s
```

### Prometheus Metrics

```yaml
# Add to monitoring stack
prometheus:
  scrape_configs:
    - job_name: 'tts'
      static_configs:
        - targets: ['stack:1885']
      metrics_path: /metrics
```

### Key Metrics to Monitor

```
# Gateway connectivity
gs_connected_gateways_total
gs_gateway_connection_duration_seconds

# Message throughput
ns_uplink_received_total
ns_downlink_attempts_total
as_uplink_forwarded_total

# Webhook delivery
as_webhook_requests_total
as_webhook_errors_total
as_webhook_latency_seconds

# System health
process_resident_memory_bytes
go_goroutines
```

### Alerting Rules

```yaml
groups:
  - name: tts
    rules:
      - alert: GatewayDisconnected
        expr: gs_connected_gateways_total < 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "No gateways connected"

      - alert: WebhookFailures
        expr: rate(as_webhook_errors_total[5m]) > 0.1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High webhook failure rate"
```

## Scaling

### Horizontal Scaling

For deployments beyond 10,000 devices:

```yaml
# docker-compose.scale.yml
services:
  stack:
    deploy:
      replicas: 3

  nginx:
    image: nginx
    ports:
      - "443:443"
      - "1700:1700/udp"
    # Configure upstream load balancing
```

### Component Separation

For very large deployments, separate components:

```yaml
# gateway-server.yml
services:
  gs:
    image: thethingsnetwork/lorawan-stack
    command: start gs

# network-server.yml
services:
  ns:
    image: thethingsnetwork/lorawan-stack
    command: start ns
```

## Troubleshooting Deployment

### Check Container Status

```bash
docker-compose ps
docker-compose logs stack --tail=100
```

### Database Connection

```bash
docker-compose exec postgres psql -U ttn -d ttn_lorawan -c "SELECT 1"
docker-compose exec redis redis-cli -a ${REDIS_PASSWORD} PING
```

### TLS Issues

```bash
# Test TLS certificate
openssl s_client -connect lorawan.olivenet.com:443

# Check certificate expiry
echo | openssl s_client -connect lorawan.olivenet.com:443 2>/dev/null | \
  openssl x509 -noout -dates
```

### Gateway Connection

```bash
# Check UDP port
nc -vzu lorawan.olivenet.com 1700

# Check WebSocket
wscat -c wss://lorawan.olivenet.com:8887/traffic/eui-0102030405060708
```

## Maintenance

### Updates

```bash
# Pull latest images
docker-compose pull

# Apply updates with zero downtime
docker-compose up -d --no-deps stack

# Run migrations if needed
docker-compose exec stack ttn-lw-stack is-db migrate
```

### Log Rotation

```yaml
# docker-compose.yml
services:
  stack:
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "5"
```

## Security Checklist

- [ ] Strong passwords for PostgreSQL and Redis
- [ ] TLS enabled for all public endpoints
- [ ] Firewall configured (only required ports open)
- [ ] Admin user 2FA enabled
- [ ] API keys have minimal required permissions
- [ ] Regular backups configured and tested
- [ ] Monitoring and alerting active
- [ ] Log rotation configured
- [ ] Security updates applied regularly
