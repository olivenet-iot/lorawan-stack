# The Things Stack - Architecture (Olivenet)

## System Overview

The Things Stack is a complete LoRaWAN Network Server consisting of multiple interconnected components. For Olivenet's 3000+ energy meter deployment, understanding this architecture is critical for scaling and customization.

## Component Architecture

### High-Level Data Flow

```
                                   ┌─────────────────┐
                                   │   ThingsBoard   │
                                   │   (External)    │
                                   └────────▲────────┘
                                            │ Webhooks/MQTT
┌─────────────────────────────────────────────────────────────────────────┐
│                          The Things Stack                                │
│                                                                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────────┐  │
│  │ Identity │    │ Gateway  │    │ Network  │    │   Application    │  │
│  │  Server  │◄──►│  Server  │◄──►│  Server  │◄──►│     Server       │  │
│  │   (IS)   │    │   (GS)   │    │   (NS)   │    │      (AS)        │  │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘    └────────┬─────────┘  │
│       │               │               │                    │            │
│       │               │          ┌────▼─────┐              │            │
│       │               │          │   Join   │              │            │
│       │               │          │  Server  │              │            │
│       │               │          │   (JS)   │              │            │
│       │               │          └──────────┘              │            │
│       │               │                                    │            │
│       ▼               ▼                                    ▼            │
│  PostgreSQL        Redis                              Webhooks          │
│                                                       PubSub            │
│                                                       MQTT              │
└─────────────────────────────────────────────────────────────────────────┘
        ▲
        │ UDP/WebSocket/MQTT
┌───────┴───────┐
│   Gateways    │
│  (3000+ EMs)  │
└───────────────┘
```

## Component Details

### 1. Identity Server (IS)
**Purpose**: Central registry for all entities
**Location**: `pkg/identityserver/`

**Responsibilities**:
- User authentication and authorization
- Organization management
- Application registry
- Gateway registry
- End device registry
- API key management
- OAuth 2.0 provider

**Database**: PostgreSQL
```
Tables:
├── accounts           # User accounts
├── organizations      # Organizations
├── applications       # Application metadata
├── end_devices        # Device EUIs and keys
├── gateways          # Gateway registrations
├── api_keys          # API credentials
├── oauth_clients     # OAuth applications
└── sessions          # User sessions
```

### 2. Gateway Server (GS)
**Purpose**: Gateway connectivity and management
**Location**: `pkg/gatewayserver/`

**Responsibilities**:
- Accept connections from gateways
- Protocol translation (UDP, BasicStation, MQTT)
- Gateway status monitoring
- Uplink deduplication
- Downlink scheduling

**Supported Protocols**:
| Protocol | Port | Implementation |
|----------|------|----------------|
| UDP Packet Forwarder | 1700/UDP | `pkg/gatewayserver/io/udp/` |
| BasicStation | 8887/WSS | `pkg/gatewayserver/io/basicstation/` |
| MQTT | 8883/MQTTS | `pkg/gatewayserver/io/mqtt/` |
| TTI Gateway | Custom | `pkg/gatewayserver/io/ttigw/` |

**Gateway Connection Flow**:
```
Gateway → GS → Authenticate (IS) → Register Connection (Redis)
                                           │
                                           ▼
                                   Start Heartbeat
                                   Route Uplinks → NS
                                   Receive Downlinks ← NS
```

### 3. Network Server (NS)
**Purpose**: LoRaWAN MAC layer processing
**Location**: `pkg/networkserver/`

**Responsibilities**:
- MAC command processing
- Adaptive Data Rate (ADR)
- Downlink scheduling
- Device session management
- Frame counter validation
- Deduplication

**Key Files**:
- `grpc_gsns.go:1493` - HandleUplink entry point
- `mac/` - MAC command handlers
- `internal/` - ADR algorithms

**Uplink Processing Flow**:
```
GS → NS.HandleUplink()
        │
        ├── Deduplicate (Redis)
        ├── Validate MIC
        ├── Process MAC Commands
        ├── Update Device State
        └── Forward to AS
```

### 4. Application Server (AS)
**Purpose**: Application layer processing
**Location**: `pkg/applicationserver/`

**Responsibilities**:
- Payload decryption
- Payload formatting (decode/encode)
- Webhook delivery
- PubSub integration
- Downlink queuing

**Integration Points**:
```
pkg/applicationserver/io/
├── formatters/      # Payload formatters
├── web/            # Webhooks
│   └── webhooks.go
├── pubsub/         # MQTT, NATS, Kafka
│   ├── mqtt/
│   └── nats/
└── packages/       # Application packages
    └── loragls/    # Geolocation
```

### 5. Join Server (JS)
**Purpose**: OTAA join handling
**Location**: `pkg/joinserver/`

**Responsibilities**:
- Join request validation
- DevNonce tracking
- Session key derivation
- Root key storage (optional)

**OTAA Join Flow**:
```
Device → Gateway → GS → NS → JS
                              │
                              ├── Validate MIC (NwkKey)
                              ├── Check DevNonce
                              ├── Derive Session Keys
                              │   ├── NwkSKey
                              │   ├── AppSKey
                              │   └── (SNwkSIntKey, FNwkSIntKey for 1.1)
                              └── Return JoinAccept
                                      │
NS ← ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
 │
 └── Schedule JoinAccept downlink
```

### 6. Console
**Purpose**: Web-based management interface
**Location**: `pkg/console/`, `pkg/webui/`

**Features**:
- User/Organization management
- Application/Device management
- Gateway management
- Live data view
- Payload formatter editor

## Data Storage

### PostgreSQL (Identity Server)
```yaml
Connection: postgres://user:pass@host:5432/ttn_lorawan

Tables:
- Entity metadata (users, apps, devices, gateways)
- API keys and OAuth clients
- Access control lists
- Audit logs
```

### Redis (Runtime State)
```yaml
Connection: redis://host:6379

Key Prefixes:
- ttn:v3:ns:devices:*     # NS device state
- ttn:v3:as:devices:*     # AS device state
- ttn:v3:gs:conn:*        # Gateway connections
- ttn:v3:is:sessions:*    # User sessions
- ttn:v3:tasks:*          # Async task queue
- ttn:v3:dedup:*          # Uplink deduplication
```

## API Architecture

### gRPC Services
All inter-component communication uses gRPC:
```protobuf
// api/ttn/lorawan/v3/
├── identityserver.proto    # IS gRPC services
├── gatewayserver.proto     # GS gRPC services
├── networkserver.proto     # NS gRPC services
├── applicationserver.proto # AS gRPC services
└── joinserver.proto        # JS gRPC services
```

### REST API (grpc-gateway)
HTTP/REST is provided via grpc-gateway:
```
POST /api/v3/applications/{application_id}/devices
GET  /api/v3/gateways/{gateway_id}
PUT  /api/v3/applications/{application_id}/webhooks/{webhook_id}
```

## Security Architecture

### Authentication Methods
1. **API Keys**: For machine-to-machine
2. **OAuth 2.0**: For user applications
3. **TLS Client Certificates**: For gateways

### Authorization Model
```
Entity Rights:
├── RIGHT_APPLICATION_INFO
├── RIGHT_APPLICATION_DEVICES_READ
├── RIGHT_APPLICATION_DEVICES_WRITE
├── RIGHT_APPLICATION_TRAFFIC_READ
├── RIGHT_GATEWAY_INFO
├── RIGHT_GATEWAY_STATUS_READ
└── RIGHT_GATEWAY_LINK
```

### TLS Configuration
```yaml
Ports:
- 88xx: TLS-enabled services
- 18xx: Non-TLS (development only)

Certificate Sources:
- File-based (cert.pem, key.pem)
- ACME (Let's Encrypt auto-renewal)
```

## Olivenet-Specific Considerations

### Scale Requirements
- 3000+ energy meters
- ~50 gateways (estimated)
- Peak: 3000 uplinks/minute (assuming 1 msg/device/min)

### Recommended Configuration
```yaml
# Network Server
ns:
  deduplication-window: 200ms
  cooldown-window: 2s

# Application Server
as:
  webhooks:
    queue-size: 1000
    workers: 16

# Gateway Server
gs:
  udp:
    workers: 8
```

### Integration Points
1. **Webhooks to ThingsBoard**: Primary data flow
2. **MQTT PubSub**: Real-time streaming option
3. **Device Provisioning API**: Bulk device import

## Monitoring Points

### Key Metrics
```
# Gateway health
gs_connected_gateways
gs_uplink_received_total
gs_downlink_sent_total

# Network Server
ns_uplink_processed_total
ns_downlink_scheduled_total
ns_mac_commands_processed_total

# Application Server
as_uplink_forwarded_total
as_webhook_sent_total
as_webhook_failed_total
```

### Health Endpoints
```
GET /healthz          # Liveness probe
GET /readyz           # Readiness probe
GET /metrics          # Prometheus metrics
```
