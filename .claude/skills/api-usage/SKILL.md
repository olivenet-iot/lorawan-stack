# API Usage Skill

## Overview

The Things Stack (TTS) API, gRPC tabanlı bir servis mimarisi kullanır ve grpc-gateway ile REST endpoint'leri otomatik olarak oluşturulur. Bu skill, API kullanımı, authentication, field mask'ler ve client development için gerekli bilgileri içerir.

## Key Concepts

### API Mimarisi
- **Proto Tanımları**: `api/ttn/lorawan/v3/` dizininde (54 .proto dosyası)
- **gRPC Services**: Her component için ayrı servis tanımları
- **REST Gateway**: `google.api.http` annotation'ları ile otomatik REST endpoint'ler
- **Go Package**: `go.thethings.network/lorawan-stack/v3/pkg/ttnpb`

### Ana Servisler

| Servis | Proto Dosyası | Açıklama |
|--------|---------------|----------|
| EntityAccess | `identityserver.proto` | Auth bilgisi sorgulama |
| EndDeviceRegistry | `end_device_services.proto` | Device CRUD (Identity Server) |
| NsEndDeviceRegistry | `networkserver.proto` | Device state (Network Server) |
| AsEndDeviceRegistry | `applicationserver.proto` | Device (Application Server) |
| JsEndDeviceRegistry | `joinserver.proto` | Device keys (Join Server) |
| GtwGs | `gatewayserver.proto` | Gateway connection |
| Ns | `networkserver.proto` | NS yönetimi |
| As | `applicationserver.proto` | AS yönetimi |

### Authentication Yöntemleri

```
AuthInfoResponse.access_method:
├── api_key        # API Key authentication
├── oauth_access_token  # OAuth2 access token
├── user_session   # Session cookie (CSRF koruması gerektirir)
└── gateway_token  # Gateway-specific token
```

## Common Tasks

### Task 1: API Key ile Authentication

**Files**: `api/ttn/lorawan/v3/identityserver.proto`, `pkg/identityserver/`

**Procedure**:
1. API Key oluştur (Console veya CLI ile)
2. gRPC metadata'ya ekle: `authorization: Bearer <API_KEY>`
3. REST için header: `Authorization: Bearer <API_KEY>`

**Code Example** (grpcurl):
```bash
# Auth info kontrolü
grpcurl -H "authorization: Bearer NNSXS.XXXX..." \
  -d '{}' \
  localhost:8884 ttn.lorawan.v3.EntityAccess/AuthInfo
```

### Task 2: Device Oluşturma (Full Registration)

**Files**:
- `api/ttn/lorawan/v3/end_device_services.proto:37` (EndDeviceRegistry)
- `api/ttn/lorawan/v3/networkserver.proto:141` (NsEndDeviceRegistry)
- `api/ttn/lorawan/v3/applicationserver.proto` (AsEndDeviceRegistry)
- `api/ttn/lorawan/v3/joinserver.proto` (JsEndDeviceRegistry)

**Procedure**:
Device registration 4 component'te yapılmalı (sıralı):

1. **Identity Server**: Device ID ve metadata
```bash
POST /applications/{app_id}/devices
```

2. **Join Server** (OTAA için): Root keys
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

### Task 3: Field Mask Kullanımı

**Files**: Tüm `*Request` message'ları

**Procedure**:
Field mask, hangi alanların döndürüleceğini veya güncelleneceğini belirtir.

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

**Yaygın Field Paths**:
- `name`, `description`, `attributes`
- `session` (aktif session bilgileri)
- `mac_state` (MAC layer durumu)
- `pending_session` (bekleyen OTAA session)
- `root_keys` (AppKey, NwkKey - sadece JS)
- `formatters` (payload formatters - sadece AS)

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
Server-Sent Events (SSE) veya gRPC stream:

```bash
# REST (SSE)
GET /events?names=gs.up.receive&identifiers.device_ids.application_ids.application_id=my-app

# gRPC
rpc Stream(StreamEventsRequest) returns (stream Event)
```

## Code Patterns

### Proto Message to JSON
```go
// ttnpb paketinde
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

| Kategori | Dosya |
|----------|-------|
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
- API key geçerliliğini kontrol et
- Header formatı: `Authorization: Bearer NNSXS.xxx...`
- API key'in gerekli rights'a sahip olduğunu doğrula

### 403 Forbidden
- API key'in entity üzerinde yetkisi yok
- Collaborator eklenmesi gerekebilir
- `rights` field'ını kontrol et

### Field Mask Errors
- Geçersiz path: Proto tanımındaki exact path kullan
- Read-only field güncelleme: `created_at`, `updated_at` gibi alanlar güncelenemez
- Nested path: `mac_settings.rx1_delay` gibi nested path'ler desteklenir

### gRPC Connection Issues
- TLS sertifika doğrulaması: `--insecure` kullanma, sertifika ekle
- Port kontrolü: gRPC default 8884 (TLS), 1884 (plain)
- Metadata sırası: `authorization` header küçük harfle

### Rate Limiting
- HTTP 429 hatası: Rate limit aşıldı
- Exponential backoff uygula
- Batch operations kullan
