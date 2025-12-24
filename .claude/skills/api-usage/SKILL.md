# API Usage Skill

## Overview

The Things Stack (TTS) API uses a gRPC-based service architecture and REST endpoints are automatically generated via grpc-gateway. This skill contains the necessary information for API usage, authentication, field masks, and client development.

## Key Concepts

### API Architecture
- **Proto Definitions**: Located in `api/ttn/lorawan/v3/` directory (54 .proto files)
- **gRPC Services**: Separate service definitions for each component
- **REST Gateway**: Automatic REST endpoints via `google.api.http` annotations
- **Go Package**: `go.thethings.network/lorawan-stack/v3/pkg/ttnpb`

### Main Services

| Service | Proto File | Description |
|---------|------------|-------------|
| EntityAccess | `identityserver.proto` | Auth info query |
| EndDeviceRegistry | `end_device_services.proto` | Device CRUD (Identity Server) |
| NsEndDeviceRegistry | `networkserver.proto` | Device state (Network Server) |
| AsEndDeviceRegistry | `applicationserver.proto` | Device (Application Server) |
| JsEndDeviceRegistry | `joinserver.proto` | Device keys (Join Server) |
| GtwGs | `gatewayserver.proto` | Gateway connection |
| Ns | `networkserver.proto` | NS management |
| As | `applicationserver.proto` | AS management |

### Authentication Methods

```
AuthInfoResponse.access_method:
├── api_key        # API Key authentication
├── oauth_access_token  # OAuth2 access token
├── user_session   # Session cookie (requires CSRF protection)
└── gateway_token  # Gateway-specific token
```

## Common Tasks

### Task 1: API Key Authentication

**Files**: `api/ttn/lorawan/v3/identityserver.proto`, `pkg/identityserver/`

**Procedure**:
1. Create API Key (via Console or CLI)
2. Add to gRPC metadata: `authorization: Bearer <API_KEY>`
3. For REST, use header: `Authorization: Bearer <API_KEY>`

**Code Example** (grpcurl):
```bash
# Auth info check
grpcurl -H "authorization: Bearer NNSXS.XXXX..." \
  -d '{}' \
  localhost:8884 ttn.lorawan.v3.EntityAccess/AuthInfo
```

### Task 2: Device Creation (Full Registration)

**Files**:
- `api/ttn/lorawan/v3/end_device_services.proto:37` (EndDeviceRegistry)
- `api/ttn/lorawan/v3/networkserver.proto:141` (NsEndDeviceRegistry)
- `api/ttn/lorawan/v3/applicationserver.proto` (AsEndDeviceRegistry)
- `api/ttn/lorawan/v3/joinserver.proto` (JsEndDeviceRegistry)

**Procedure**:
Device registration must be done in 4 components (sequentially):

1. **Identity Server**: Device ID and metadata
```bash
POST /applications/{app_id}/devices
```

2. **Join Server** (for OTAA): Root keys
```bash
PUT /js/applications/{app_id}/devices/{device_id}
```

3. **Network Server**: MAC settings, frequency plan
```bash
PUT /ns/applications/{app_id}/devices/{device_id}
```

4. **Application Server**: Formatters, locations
```bash
PUT /as/applications/{app_id}/devices/{device_id}
```

### Task 3: Field Mask Usage

**Files**: All `*Request` messages

**Procedure**:
Field mask specifies which fields to return or update.

**Get Request**:
```json
{
  "end_device_ids": {
    "application_ids": {"application_id": "my-app"},
    "device_id": "my-device"
  },
  "field_mask": {
    "paths": ["name", "description", "attributes", "session"]
  }
}
```

**Update Request**:
```json
{
  "end_device": {
    "ids": {...},
    "name": "New Name"
  },
  "field_mask": {
    "paths": ["name"]
  }
}
```

**Common Field Paths**:
- `name`, `description`, `attributes`
- `session` (active session information)
- `mac_state` (MAC layer state)
- `pending_session` (pending OTAA session)
- `root_keys` (AppKey, NwkKey - JS only)
- `formatters` (payload formatters - AS only)

### Task 4: Batch Operations

**Files**: `api/ttn/lorawan/v3/end_device_services.proto:117` (EndDeviceBatchRegistry)

**Procedure**:
```bash
# Batch Get
GET /applications/{app_id}/devices/batch?device_ids=dev1&device_ids=dev2

# Batch Delete (atomic)
DELETE /applications/{app_id}/devices/batch
```

### Task 5: Event Streaming

**Files**: `api/ttn/lorawan/v3/events.proto`

**Procedure**:
Server-Sent Events (SSE) or gRPC stream:

```bash
# REST (SSE)
GET /events?names=gs.up.receive&identifiers.device_ids.application_ids.application_id=my-app

# gRPC
rpc Stream(StreamEventsRequest) returns (stream Event)
```

## Code Patterns

### Proto Message to JSON
```go
// In ttnpb package
import "go.thethings.network/lorawan-stack/v3/pkg/ttnpb"

device := &ttnpb.EndDevice{
    Ids: &ttnpb.EndDeviceIdentifiers{
        ApplicationIds: &ttnpb.ApplicationIdentifiers{ApplicationId: "my-app"},
        DeviceId:       "my-device",
    },
}
```

### REST URL Patterns
```
# Entity pattern
/applications/{application_id}/devices/{device_id}

# Component-specific
/ns/applications/{application_id}/devices/{device_id}  # Network Server
/as/applications/{application_id}/devices/{device_id}  # Application Server
/js/applications/{application_id}/devices/{device_id}  # Join Server

# Batch operations
/applications/{application_id}/devices/batch

# Service endpoints
/ns/dev_addr          # Generate DevAddr
/ns/default_mac_settings/{frequency_plan_id}/{lorawan_phy_version}
```

### gRPC Service Patterns
```protobuf
// Inter-component services (internal use)
service GsNs {
  rpc HandleUplink(UplinkMessage) returns (google.protobuf.Empty);
  rpc ReportTxAcknowledgment(GatewayTxAcknowledgment) returns (google.protobuf.Empty);
}

// Client-facing services
service EndDeviceRegistry {
  rpc Create(CreateEndDeviceRequest) returns (EndDevice);
  rpc Get(GetEndDeviceRequest) returns (EndDevice);
  rpc Update(UpdateEndDeviceRequest) returns (EndDevice);
  rpc Delete(EndDeviceIdentifiers) returns (google.protobuf.Empty);
}
```

## Configuration Reference

### API Server Ports
```yaml
# config/ttn-lw-stack.yml
http:
  listen: ":1885"
  listen-tls: ":8885"

grpc:
  listen: ":1884"
  listen-tls: ":8884"
```

### Rate Limiting
```yaml
rate-limiting:
  memory:
    # Request rate limiting
    max-per-second: 100
    # Burst size
    burst-size: 20
```

### OAuth2 Configuration
```yaml
is:
  oauth:
    ui:
      canonical-url: "https://example.com/oauth"
    mount: "/oauth"
```

## File References

| Category | File |
|----------|------|
| All Proto Files | `api/ttn/lorawan/v3/*.proto` |
| Identity Server Proto | `api/ttn/lorawan/v3/identityserver.proto` |
| Device Services Proto | `api/ttn/lorawan/v3/end_device_services.proto` |
| Network Server Proto | `api/ttn/lorawan/v3/networkserver.proto` |
| Application Server Proto | `api/ttn/lorawan/v3/applicationserver.proto` |
| Join Server Proto | `api/ttn/lorawan/v3/joinserver.proto` |
| Gateway Server Proto | `api/ttn/lorawan/v3/gatewayserver.proto` |
| Events Proto | `api/ttn/lorawan/v3/events.proto` |
| Messages Proto | `api/ttn/lorawan/v3/messages.proto` |
| End Device Proto | `api/ttn/lorawan/v3/end_device.proto` |
| Identifiers Proto | `api/ttn/lorawan/v3/identifiers.proto` |
| Go Package | `pkg/ttnpb/` (generated) |

## Troubleshooting

### 401 Unauthorized
- Check API key validity
- Header format: `Authorization: Bearer NNSXS.xxx...`
- Verify API key has required rights

### 403 Forbidden
- API key has no permission on entity
- May need to add collaborator
- Check `rights` field

### Field Mask Errors
- Invalid path: Use exact path from proto definition
- Updating read-only field: Fields like `created_at`, `updated_at` cannot be updated
- Nested path: Nested paths like `mac_settings.rx1_delay` are supported

### gRPC Connection Issues
- TLS certificate validation: Don't use `--insecure`, add certificate
- Port check: gRPC default 8884 (TLS), 1884 (plain)
- Metadata order: `authorization` header in lowercase

### Rate Limiting
- HTTP 429 error: Rate limit exceeded
- Apply exponential backoff
- Use batch operations
