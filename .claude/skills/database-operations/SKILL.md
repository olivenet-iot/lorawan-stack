# Database Operations Skill

## Overview

The Things Stack iki ana veri deposu kullanır: PostgreSQL (Identity Server için) ve Redis (NS, AS, JS, GS için real-time state). Bu skill, database schema, migrations, backup/restore ve query optimization konularını kapsar.

## Key Concepts

### Storage Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Storage Layer                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  PostgreSQL (Identity Server)                                │
│  ├── Users, Organizations                                    │
│  ├── Applications, Gateways (registry)                      │
│  ├── End Devices (metadata only)                            │
│  ├── API Keys, OAuth tokens                                 │
│  └── Invitations, Contact info                              │
│                                                              │
│  Redis (Runtime State)                                       │
│  ├── Network Server: Device sessions, MAC state             │
│  ├── Application Server: Device state, links                │
│  ├── Join Server: Root keys, session keys                   │
│  ├── Gateway Server: Connection state                       │
│  └── Events: Pub/Sub channels                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Data Distribution

| Data Type | Storage | Component |
|-----------|---------|-----------|
| User accounts | PostgreSQL | IS |
| Organizations | PostgreSQL | IS |
| Applications (metadata) | PostgreSQL | IS |
| Gateways (metadata) | PostgreSQL | IS |
| Devices (metadata) | PostgreSQL | IS |
| API keys | PostgreSQL | IS |
| OAuth tokens | PostgreSQL | IS |
| Device sessions | Redis | NS |
| MAC state | Redis | NS |
| Frame counters | Redis | NS |
| Root keys (AppKey, NwkKey) | Redis | JS |
| Session keys | Redis | JS |
| Application links | Redis | AS |
| Gateway connections | Redis | GS |

## PostgreSQL (Identity Server)

### Migration System

**Location**: `pkg/identityserver/store/migrations/`

**Files**:
```
pkg/identityserver/store/migrations/
├── migrations.go            # Migration registry
├── util.go                  # Helper functions
└── 20220520000000_v3_20.go  # Migration definitions
```

**Run Migrations**:
```bash
# CLI command
ttn-lw-stack is-db migrate

# Docker
docker-compose exec stack ttn-lw-stack is-db migrate
```

**Check Status**:
```bash
ttn-lw-stack is-db version
```

### Database Tables

```sql
-- Core entities
users
organizations
applications
gateways
end_devices

-- Relationships
memberships              -- User/org memberships
api_keys                 -- API key storage
oauth_access_tokens      -- OAuth tokens
oauth_authorization_codes
oauth_client_authorizations

-- Metadata
attributes               -- Entity attributes
contact_info            -- Contact information
pictures                -- Entity pictures
locations               -- Entity locations

-- Invitations & validation
invitations
email_validations
```

### Connection Configuration

```yaml
# ttn-lw-stack.yml
is:
  database-uri: "postgres://user:password@localhost:5432/ttn_lorawan?sslmode=disable"

  # Connection pool
  database:
    max-open-connections: 100
    max-idle-connections: 10
    conn-max-lifetime: 1h
```

### Query Patterns

**Store Interface** (`pkg/identityserver/store/`):
```go
type UserStore interface {
    CreateUser(ctx context.Context, user *ttnpb.User) (*ttnpb.User, error)
    GetUser(ctx context.Context, id *ttnpb.UserIdentifiers, fieldMask *types.FieldMask) (*ttnpb.User, error)
    UpdateUser(ctx context.Context, user *ttnpb.User, fieldMask *types.FieldMask) (*ttnpb.User, error)
    DeleteUser(ctx context.Context, id *ttnpb.UserIdentifiers) error
    FindUsers(ctx context.Context, ids []*ttnpb.UserIdentifiers, fieldMask *types.FieldMask) ([]*ttnpb.User, error)
}
```

## Redis (Component State)

### Key Naming Convention

```
{component}:{type}:{identifier}

Examples:
ns:uid:{app-id}:{device-id}           # NS device by UID
ns:addr:{dev-addr}:current            # NS device by current DevAddr
ns:addr:{dev-addr}:pending            # NS device by pending DevAddr
ns:eui:{join-eui}:{dev-eui}           # NS device by EUI

as:uid:{app-id}:{device-id}           # AS device state
as:link:{app-id}                      # AS application link

js:id:{join-eui}:{dev-eui}:{session-key-id}  # JS session keys
js:ids:{join-eui}:{dev-eui}                  # JS device keys

gs:uid:{gateway-id}                   # GS gateway state
```

### Network Server Redis Keys

**Location**: `pkg/networkserver/redis/`

```go
// pkg/networkserver/redis/registry.go

// Device by UID
func UIDKey(r keyer, uid string) string {
    return r.Key("uid", uid)
}

// Device by DevAddr
func (r *DeviceRegistry) addrKey(devAddr types.DevAddr) string {
    return r.Key("addr", devAddr.String())
}

func CurrentAddrKey(addrKey string) string {
    return addrKey + ":current"
}

func PendingAddrKey(addrKey string) string {
    return addrKey + ":pending"
}
```

**Data Structure**:
```
ns:uid:{uid}
├── ids                    # EndDeviceIdentifiers
├── session                # Active session
├── pending_session        # Pending OTAA session
├── mac_state             # Current MAC state
├── mac_settings          # MAC settings
└── ...
```

### Application Server Redis Keys

**Location**: `pkg/applicationserver/redis/`

```go
// Device state
as:uid:{app-id}:{device-id}

// Application link
as:link:{app-id}
```

### Join Server Redis Keys

**Location**: `pkg/joinserver/redis/`

```go
// Session keys (encrypted)
js:id:{join-eui}:{dev-eui}:{session-key-id}

// Device keys (root keys)
js:ids:{join-eui}:{dev-eui}
```

### Connection Configuration

```yaml
# ttn-lw-stack.yml
redis:
  address: "localhost:6379"
  password: ""
  database: 0

  # Connection pool
  pool-size: 10

  # TLS (optional)
  tls:
    require: false
```

## Common Tasks

### Task 1: Database Backup

**PostgreSQL**:
```bash
# Full backup
pg_dump -h localhost -U ttn -d ttn_lorawan > backup.sql

# Compressed
pg_dump -h localhost -U ttn -d ttn_lorawan | gzip > backup.sql.gz

# Custom format (for pg_restore)
pg_dump -h localhost -U ttn -d ttn_lorawan -Fc > backup.dump
```

**Redis**:
```bash
# Trigger BGSAVE
redis-cli BGSAVE

# Copy RDB file
cp /var/lib/redis/dump.rdb backup-$(date +%Y%m%d).rdb

# Or use redis-cli
redis-cli --rdb backup.rdb
```

### Task 2: Database Restore

**PostgreSQL**:
```bash
# From SQL dump
psql -h localhost -U ttn -d ttn_lorawan < backup.sql

# From compressed
gunzip -c backup.sql.gz | psql -h localhost -U ttn -d ttn_lorawan

# From custom format
pg_restore -h localhost -U ttn -d ttn_lorawan backup.dump
```

**Redis**:
```bash
# Stop Redis
systemctl stop redis

# Replace RDB
cp backup.rdb /var/lib/redis/dump.rdb

# Start Redis
systemctl start redis
```

### Task 3: Query Device by DevAddr

**Using ttn-lw-cli**:
```bash
ttn-lw-cli end-devices get \
  --application-id my-app \
  --device-id my-device \
  --session.dev-addr
```

**Direct Redis Query**:
```bash
# Find device UID by DevAddr
redis-cli GET "ns:addr:260BABCD:current"

# Get device data
redis-cli HGETALL "ns:uid:my-app:my-device"
```

### Task 4: Run Migrations

**Identity Server**:
```bash
# Check current version
ttn-lw-stack is-db version

# Run migrations
ttn-lw-stack is-db migrate

# Create new migration
ttn-lw-stack is-db create-migration "description"
```

### Task 5: Reset Device Session (Redis)

```bash
# Delete device session from NS
redis-cli DEL "ns:uid:my-app:my-device"

# Clear DevAddr mapping
redis-cli DEL "ns:addr:260BABCD:current"

# Device will need to rejoin (OTAA) or be re-provisioned (ABP)
```

### Task 6: Monitor Redis Memory

```bash
# Memory usage
redis-cli INFO memory

# Key count by pattern
redis-cli --scan --pattern "ns:uid:*" | wc -l

# Big keys
redis-cli --bigkeys

# Memory for specific key
redis-cli MEMORY USAGE "ns:uid:my-app:my-device"
```

## Code Patterns

### Store Transaction Pattern

```go
// pkg/identityserver/store/
func (s *store) Transact(ctx context.Context, fc func(context.Context, Store) error) error {
    tx, err := s.DB.BeginTx(ctx, nil)
    if err != nil {
        return err
    }
    defer tx.Rollback()

    if err := fc(ctx, &store{DB: tx}); err != nil {
        return err
    }
    return tx.Commit()
}
```

### Redis Proto Storage

```go
// pkg/redis/redis.go
func SetProto(ctx context.Context, r Redis, k string, pb proto.Message, expiration time.Duration) error
func GetProto(ctx context.Context, r Redis, k string, pb proto.Message) error
```

### Device Registry Pattern

```go
// pkg/networkserver/redis/registry.go
type DeviceRegistry struct {
    Redis   *ttnredis.Client
    LockTTL time.Duration
}

func (r *DeviceRegistry) GetByID(ctx context.Context, appID *ttnpb.ApplicationIdentifiers, devID string, paths []string) (*ttnpb.EndDevice, context.Context, error)
func (r *DeviceRegistry) SetByID(ctx context.Context, appID *ttnpb.ApplicationIdentifiers, devID string, paths []string, f func(context.Context, *ttnpb.EndDevice) (*ttnpb.EndDevice, []string, error)) (*ttnpb.EndDevice, context.Context, error)
```

## Configuration Reference

### PostgreSQL Configuration

```yaml
is:
  database-uri: "postgres://user:password@localhost:5432/ttn_lorawan?sslmode=disable"

  database:
    # Connection pool
    max-open-connections: 100
    max-idle-connections: 10
    conn-max-lifetime: 1h

    # Timeouts
    read-timeout: 30s
    write-timeout: 30s
```

### Redis Configuration

```yaml
redis:
  address: "localhost:6379"
  password: ""
  database: 0

  # Connection pool
  pool-size: 10
  min-idle-connections: 0

  # Timeouts
  connect-timeout: 5s
  read-timeout: 3s
  write-timeout: 3s

  # TLS
  tls:
    require: false
    root-ca: ""
    certificate: ""
    key: ""

  # Cluster mode (optional)
  failover:
    enable: false
    master-name: "mymaster"
    addresses:
      - "sentinel1:26379"
      - "sentinel2:26379"
```

### Component-specific Redis

```yaml
# Network Server
ns:
  redis:
    address: "redis-ns:6379"
    database: 0

# Application Server
as:
  redis:
    address: "redis-as:6379"
    database: 1

# Join Server
js:
  redis:
    address: "redis-js:6379"
    database: 2
```

## File References

| Kategori | Dosya |
|----------|-------|
| IS Store | `pkg/identityserver/store/` |
| IS Migrations | `pkg/identityserver/store/migrations/` |
| NS Redis | `pkg/networkserver/redis/` |
| NS Registry | `pkg/networkserver/redis/registry.go` |
| AS Redis | `pkg/applicationserver/redis/` |
| JS Redis | `pkg/joinserver/redis/` |
| Redis Util | `pkg/redis/` |
| Database Config | Component config files |

## Troubleshooting

### PostgreSQL Bağlantı Hatası
- Connection string formatını kontrol et
- Database'in var olduğunu doğrula
- User yetkilerini kontrol et
- `pg_isready -h localhost -U ttn` ile test et

### Migration Hatası
- Önceki migration'ların tamamlandığını doğrula
- Database schema uyumluluğunu kontrol et
- Log'ları incele

### Redis Memory Yetersiz
- `maxmemory` ayarını kontrol et
- Eski key'leri temizle
- RDB/AOF boyutunu kontrol et
- `MEMORY DOCTOR` çalıştır

### Device State Kayıp
- Redis persistence (RDB/AOF) aktif olmalı
- Backup'tan restore et
- ABP: Session yeniden configure et
- OTAA: Device rejoin yapacak

### Slow Queries
- PostgreSQL: `pg_stat_statements` enable et
- Redis: `SLOWLOG GET 10` ile yavaş komutları bul
- Index eksikliğini kontrol et

### Connection Pool Exhausted
- `max-open-connections` artır
- Bağlantı leaks kontrol et
- Idle connection timeout ayarla
