# Stack Internals Skill

## Overview

The Things Stack internal architecture consists of a microservice-like component structure, gRPC-based inter-service communication, event system, and cluster mode. This skill covers the stack's internal workings and component interactions.

## Key Concepts

### Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    The Things Stack                          │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ Gateway  │  │ Network  │  │Application│  │ Identity │    │
│  │ Server   │──│ Server   │──│ Server    │  │ Server   │    │
│  │ (GS)     │  │ (NS)     │  │ (AS)      │  │ (IS)     │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
│        │            │              │              │          │
│        │       ┌────┴────┐        │              │          │
│        └───────│  Join   │────────┘              │          │
│                │ Server  │                       │          │
│                │  (JS)   │                       │          │
│                └─────────┘                       │          │
├─────────────────────────────────────────────────────────────┤
│                     Storage Layer                            │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │   PostgreSQL     │  │      Redis       │                 │
│  │   (IS data)      │  │  (NS/AS/JS/GS)   │                 │
│  └──────────────────┘  └──────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

### Inter-Component gRPC Services

| Service | From | To | Purpose |
|---------|------|-------|---------|
| GsNs | Gateway Server | Network Server | Uplink handling |
| NsGs | Network Server | Gateway Server | Downlink scheduling |
| NsAs | Network Server | Application Server | Uplink forwarding |
| AsNs | Application Server | Network Server | Downlink queue |
| NsJs | Network Server | Join Server | Join handling |
| AsJs | Application Server | Join Server | AppSKey request |

### Request Flow (Uplink)

```
1. Gateway receives uplink
   └── pkg/gatewayserver/io/{udp,semtechws,mqtt}/

2. Gateway Server processes
   ├── pkg/gatewayserver/gatewayserver.go
   └── pkg/gatewayserver/upstream/ns/ns.go:98 (HandleUplink)

3. Network Server receives (GsNs service)
   ├── pkg/networkserver/grpc_gsns.go:1493 (HandleUplink)
   ├── pkg/networkserver/grpc_gsns.go:73 (deduplicateUplink)
   └── Device matching, MIC verification

4. Application Server receives (NsAs service)
   ├── pkg/applicationserver/grpc.go:133 (HandleUplink)
   ├── pkg/applicationserver/applicationserver.go:434 (processUp)
   └── pkg/applicationserver/payload.go:119 (decryptAndDecodeUplink)

5. Integrations receive
   └── pkg/applicationserver/io/{mqtt,web,pubsub}/
```

### Request Flow (Downlink)

```
1. Application sends downlink
   └── pkg/applicationserver/grpc.go (DownlinkQueuePush)

2. Application Server queues
   └── pkg/applicationserver/applicationserver.go

3. Network Server processes (AsNs service)
   ├── pkg/networkserver/grpc_asns.go
   └── Queue in device session

4. Network Server schedules on uplink
   └── pkg/networkserver/downlink.go

5. Gateway Server transmits (NsGs service)
   ├── pkg/gatewayserver/gatewayserver.go
   └── pkg/gatewayserver/io/{protocol}/
```

## Component Details

### Identity Server (IS)

**Location**: `pkg/identityserver/`

**Responsibilities**:
- User, organization management
- Application, gateway, device registry (metadata)
- OAuth2 provider
- API key management
- Rights/permissions

**Storage**: PostgreSQL
```
pkg/identityserver/store/
├── migrations/          # Database migrations
├── user_store.go       # User CRUD
├── application_store.go # Application CRUD
├── gateway_store.go    # Gateway CRUD
├── end_device_store.go # Device CRUD (metadata only)
└── ...
```

### Network Server (NS)

**Location**: `pkg/networkserver/`

**Responsibilities**:
- LoRaWAN MAC layer
- Device session management
- Frame counter tracking
- MAC command processing
- Downlink scheduling
- ADR

**Key Files**:
```
pkg/networkserver/
├── networkserver.go     # Main component
├── grpc_gsns.go        # GsNs service (uplink from GS)
├── grpc_asns.go        # AsNs service (downlink from AS)
├── grpc_nsjs.go        # NsJs client (to JS)
├── downlink.go         # Downlink scheduling
├── mac/                # MAC command handlers
└── redis/              # Device state storage
```

**Storage**: Redis
```
Keys:
├── ns:uid:{app-id}:{device-id}     # Device by UID
├── ns:addr:{dev-addr}:current      # Device by DevAddr
└── ns:eui:{join-eui}:{dev-eui}     # Device by EUI
```

### Application Server (AS)

**Location**: `pkg/applicationserver/`

**Responsibilities**:
- Payload encryption/decryption
- Payload formatting (encode/decode)
- Integration management (webhooks, MQTT, pub/sub)
- Downlink queue management
- Location services

**Key Files**:
```
pkg/applicationserver/
├── applicationserver.go  # Main component
├── grpc.go              # NsAs service (uplink from NS)
├── payload.go           # Payload processing
├── io/
│   ├── mqtt/            # MQTT integration
│   ├── web/             # Webhook integration
│   ├── pubsub/          # Pub/Sub integration
│   ├── packages/        # Application packages
│   └── formatters/      # Payload formatters
└── redis/               # State storage
```

**Storage**: Redis
```
Keys:
├── as:uid:{app-id}:{device-id}  # Device state
└── as:link:{app-id}             # Application link state
```

### Gateway Server (GS)

**Location**: `pkg/gatewayserver/`

**Responsibilities**:
- Gateway connections (UDP, WebSocket, MQTT, gRPC)
- Uplink forwarding to NS
- Downlink transmission
- Gateway status tracking
- Duty cycle management

**Key Files**:
```
pkg/gatewayserver/
├── gatewayserver.go    # Main component
├── upstream/
│   └── ns/ns.go       # Forward to Network Server
├── io/
│   ├── udp/           # UDP Packet Forwarder
│   ├── semtechws/     # BasicStation (WebSocket)
│   ├── mqtt/          # MQTT protocol
│   ├── grpc/          # Native gRPC
│   └── ttigw/         # TTI Gateway
└── scheduling/        # Downlink scheduling
```

### Join Server (JS)

**Location**: `pkg/joinserver/`

**Responsibilities**:
- Root key storage (AppKey, NwkKey)
- Join request processing
- Session key derivation
- Device claiming

**Key Files**:
```
pkg/joinserver/
├── joinserver.go       # Main component
├── grpc_nsjs.go       # NsJs service (from NS)
├── grpc_asjs.go       # AsJs service (from AS)
└── redis/             # Key storage
```

**Storage**: Redis
```
Keys:
├── js:id:{join-eui}:{dev-eui}:{session-key-id}  # Session keys
└── js:ids:{join-eui}:{dev-eui}                  # Device keys
```

## Event System

### Event Types

```protobuf
// api/ttn/lorawan/v3/events.proto

message Event {
  string name = 1;                    // e.g., "gs.up.receive"
  google.protobuf.Timestamp time = 2;
  repeated EntityIdentifiers identifiers = 3;
  google.protobuf.Any data = 4;
  string correlation_id = 5;
  string origin = 6;
  string context = 7;
  string visibility = 8;
  string authentication = 9;
  string remote_ip = 10;
  string user_agent = 11;
  string unique_id = 12;
}
```

### Common Events

| Event | Component | Description |
|-------|-----------|-------------|
| `gs.up.receive` | GS | Gateway received uplink |
| `gs.down.send` | GS | Gateway sent downlink |
| `gs.status.receive` | GS | Gateway status received |
| `ns.up.receive` | NS | NS processed uplink |
| `ns.up.forward` | NS | NS forwarded to AS |
| `ns.down.schedule` | NS | NS scheduled downlink |
| `as.up.receive` | AS | AS received uplink |
| `as.up.forward` | AS | AS forwarded to integration |
| `as.down.push` | AS | Downlink queued |
| `js.join.accept` | JS | Join accepted |

### Event Streaming

```bash
# REST (Server-Sent Events)
GET /events?names=gs.up.receive&identifiers.device_ids.application_ids.application_id=my-app

# gRPC
rpc Stream(StreamEventsRequest) returns (stream Event)
```

## Cluster Mode

### Configuration

```yaml
# Single instance (all components)
cluster:
  join: ""
  name: ""
  identity-server: ""      # localhost
  gateway-server: ""       # localhost
  network-server: ""       # localhost
  application-server: ""   # localhost
  join-server: ""          # localhost

# Distributed mode
cluster:
  join: "cluster.local:1883"
  name: "ns-1"
  identity-server: "is.cluster.local:8884"
  gateway-server: "gs.cluster.local:8884"
  network-server: ""       # This instance
  application-server: "as.cluster.local:8884"
  join-server: "js.cluster.local:8884"
```

### Service Discovery

```go
// pkg/cluster/
// Components discover each other via:
// 1. Static configuration
// 2. Consul (if configured)
// 3. Kubernetes DNS
```

## Health Checks

### Endpoints

```bash
# HTTP health check
GET /healthz  # Returns 200 if healthy

# gRPC health check
grpc.health.v1.Health/Check
```

### Component Health

```go
// Each component implements:
type Component interface {
    RegisterHandlers(s *Server)
    RegisterServices(s *grpc.Server)
    RegisterTaskStarter()
}
```

## Common Tasks

### Task 1: Trace Uplink Flow

**Files**:
```
1. pkg/gatewayserver/io/udp/udp.go        # Gateway receives
2. pkg/gatewayserver/upstream/ns/ns.go:98  # Forward to NS
3. pkg/networkserver/grpc_gsns.go:1493     # NS processes
4. pkg/applicationserver/grpc.go:133       # AS receives
5. pkg/applicationserver/io/web/webhooks.go # Webhook sends
```

### Task 2: Debug Inter-Component Communication

**Procedure**:
```bash
# Enable gRPC logging
log:
  level: debug

# Check cluster connectivity
GET /healthz

# Monitor events
GET /events?names=*
```

### Task 3: Component Configuration

**Files**: `pkg/*/config.go`

```go
// Each component has its own config struct
type Config struct {
    // Component-specific settings
}

// Registered via Cobra
func init() {
    Root.AddCommand(nsCommand)
}
```

## Code Patterns

### Component Registration
```go
// pkg/component/component.go
type Component interface {
    Context() context.Context
    Close() error
}

// Registration
c := component.New(config)
c.RegisterGRPC(server)
c.RegisterWeb(server)
```

### gRPC Service Implementation
```go
// Pattern for inter-component services
type nsGsServer struct {
    ttnpb.UnimplementedGsNsServer
    ns *NetworkServer
}

func (s *nsGsServer) HandleUplink(ctx context.Context, up *ttnpb.UplinkMessage) (*emptypb.Empty, error) {
    // Implementation
}
```

### Context Propagation
```go
// Correlation ID propagates through all components
ctx = log.NewContextWithField(ctx, "correlation_id", correlationID)

// Rights/auth context
ctx = rights.NewContext(ctx, rights.Rights{...})
```

## Configuration Reference

### Component Ports
```yaml
http:
  listen: ":1885"
  listen-tls: ":8885"

grpc:
  listen: ":1884"
  listen-tls: ":8884"
```

### Logging
```yaml
log:
  level: info    # debug, info, warn, error
  format: json   # json, console
```

### TLS
```yaml
tls:
  source: file
  root-ca: /path/to/ca.pem
  certificate: /path/to/cert.pem
  key: /path/to/key.pem
```

## File References

| Category | File |
|----------|------|
| Component Base | `pkg/component/component.go` |
| Gateway Server | `pkg/gatewayserver/gatewayserver.go` |
| Network Server | `pkg/networkserver/networkserver.go` |
| Application Server | `pkg/applicationserver/applicationserver.go` |
| Identity Server | `pkg/identityserver/identityserver.go` |
| Join Server | `pkg/joinserver/joinserver.go` |
| GsNs Handler | `pkg/networkserver/grpc_gsns.go:1493` |
| NsAs Handler | `pkg/applicationserver/grpc.go:133` |
| GS Upstream | `pkg/gatewayserver/upstream/ns/ns.go:98` |
| Events Proto | `api/ttn/lorawan/v3/events.proto` |
| Cluster | `pkg/cluster/` |
| Rights | `pkg/auth/rights/` |

## Troubleshooting

### Component Connection Error
- Check cluster configuration
- Validate TLS certificates
- Check ports are open

### Event Loss
- Check event pubsub connection
- Verify Redis connection

### Authorization Error
- Check API key rights
- Verify auth info is propagated in context
- Check Identity Server connection

### Uplink Not Reaching AS
- Check NS-AS gRPC connection
- Verify device is registered in AS
- Check application link status

### Downlink Cannot Be Scheduled
- Check NS-GS connection
- Verify gateway is connected
- Check duty cycle limit
