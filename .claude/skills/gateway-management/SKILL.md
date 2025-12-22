# Gateway Management Skill

## Overview

Gateway yönetimi, The Things Stack'e gateway bağlantıları, yapılandırma, protokol seçimi ve durum izleme işlemlerini kapsar. Bu skill, gateway registration, protokol seçenekleri ve operasyonel yönetim için gerekli bilgileri içerir.

## Key Concepts

### Desteklenen Gateway Protokolleri

| Protokol | Implementasyon | Port | Açıklama |
|----------|---------------|------|----------|
| UDP Packet Forwarder | `pkg/gatewayserver/io/udp/` | 1700 | Semtech UDP protocol |
| BasicStation (LNS) | `pkg/gatewayserver/io/semtechws/` | 8887 | WebSocket-based |
| MQTT | `pkg/gatewayserver/io/mqtt/` | 1882/8882 | MQTT v3.1.1 |
| TTI Gateway | `pkg/gatewayserver/io/ttigw/` | - | TTI proprietary |
| gRPC | `pkg/gatewayserver/io/grpc/` | 8884 | Native gRPC |

### Gateway Servisleri

```protobuf
// api/ttn/lorawan/v3/gatewayserver.proto

service GtwGs {
  // Gateway bağlantısı (bidirectional stream)
  rpc LinkGateway(stream GatewayUp) returns (stream GatewayDown);
  // Concentrator config
  rpc GetConcentratorConfig(Empty) returns (ConcentratorConfig);
  // MQTT connection info
  rpc GetMQTTConnectionInfo(GatewayIdentifiers) returns (MQTTConnectionInfo);
}

service NsGs {
  // Network Server'dan downlink scheduling
  rpc ScheduleDownlink(DownlinkMessage) returns (ScheduleDownlinkResponse);
}

service Gs {
  // Connection stats
  rpc GetGatewayConnectionStats(GatewayIdentifiers) returns (GatewayConnectionStats);
  rpc BatchGetGatewayConnectionStats(BatchGetGatewayConnectionStatsRequest) returns (BatchGetGatewayConnectionStatsResponse);
}
```

### Gateway Veri Yapısı

```protobuf
// api/ttn/lorawan/v3/gateway.proto:106
message Gateway {
  GatewayIdentifiers ids = 1;      // gateway_id, eui
  string name = 4;
  string description = 5;
  map<string, string> attributes = 6;
  repeated ContactInfo contact_info = 7;
  GatewayVersionIdentifiers version_ids = 8;

  // Location
  repeated GatewayAntenna antennas = 16;  // Antenna configurations
  Location location = 23;                  // Gateway location

  // Configuration
  string frequency_plan_id = 9;           // Required for operation
  repeated string frequency_plan_ids = 20; // Multiple frequency plans
  bool schedule_downlink_late = 14;
  bool enforce_duty_cycle = 15;
  DownlinkPathConstraint downlink_path_constraint = 17;
  bool schedule_anytime_delay = 18;
  bool update_location_from_status = 21;

  // Status
  bool status_public = 10;
  bool location_public = 11;
  bool auto_update = 22;
}
```

## Common Tasks

### Task 1: Gateway Registration

**Files**:
- `api/ttn/lorawan/v3/gateway_services.proto`
- `api/ttn/lorawan/v3/gateway.proto`

**Procedure**:

```bash
POST /gateways
{
  "gateway": {
    "ids": {
      "gateway_id": "my-gateway",
      "eui": "B827EBFFFE123456"
    },
    "name": "My LoRa Gateway",
    "description": "Office rooftop gateway",
    "frequency_plan_id": "EU_863_870_TTN",
    "status_public": true,
    "location_public": true,
    "enforce_duty_cycle": true,
    "schedule_downlink_late": false,
    "antennas": [{
      "gain": 3.0,
      "location": {
        "latitude": 52.3676,
        "longitude": 4.9041,
        "altitude": 25,
        "source": "SOURCE_REGISTRY"
      }
    }]
  }
}
```

### Task 2: UDP Packet Forwarder Yapılandırma

**Files**:
- `pkg/gatewayserver/io/udp/udp.go`
- `pkg/gatewayserver/io/udp/config.go`

**Gateway global_conf.json**:
```json
{
  "gateway_conf": {
    "gateway_ID": "B827EBFFFE123456",
    "server_address": "eu1.cloud.thethings.network",
    "serv_port_up": 1700,
    "serv_port_down": 1700,
    "keepalive_interval": 10,
    "stat_interval": 30,
    "push_timeout_ms": 100,
    "forward_crc_valid": true,
    "forward_crc_error": false,
    "forward_crc_disabled": false
  }
}
```

**Server Config**:
```yaml
# ttn-lw-stack.yml
gs:
  udp:
    listeners:
      - ":1700"
    # Firewall settings
    rate-limiting:
      enable: true
      messages: 10
      messages-size: 10000
      messages-jitter: 0.1
```

### Task 3: BasicStation (LNS) Yapılandırma

**Files**:
- `pkg/gatewayserver/io/semtechws/ws.go`
- `pkg/gatewayserver/io/semtechws/lbslns/`

**Gateway tc.uri file**:
```
wss://eu1.cloud.thethings.network:8887
```

**Gateway tc.key file** (API Key):
```
Authorization: Bearer NNSXS.XXXXXXXXXXXXXXXXXXXXXXXX.YYYYYYYYYYYY
```

**Server Config**:
```yaml
gs:
  basic-station:
    listen: ":8887"
    listen-tls: ":8887"
    use-traffic-tls-address: true
```

**LNS Protocol Flow**:
```
1. Gateway connects via WebSocket
2. Gateway sends VERSION message
3. Server responds with ROUTER_CONFIG
4. Gateway sends UPDF (uplink frames)
5. Server sends DNMSG (downlink messages)
```

### Task 4: MQTT Gateway Yapılandırma

**Files**:
- `pkg/gatewayserver/io/mqtt/mqtt.go`
- `pkg/gatewayserver/io/mqtt/topics/`

**MQTT Connection**:
```bash
# Get connection info
GET /gs/gateways/{gateway_id}/mqtt-connection-info

# Response
{
  "public_address": "eu1.cloud.thethings.network:8882",
  "public_tls_address": "eu1.cloud.thethings.network:8882",
  "username": "my-gateway@ttn"
}
```

**MQTT Topics**:
```
# Uplink (gateway → server)
v3/{gateway_id}/up

# Downlink (server → gateway)
v3/{gateway_id}/down

# Status
v3/{gateway_id}/status
```

**Server Config**:
```yaml
gs:
  mqtt:
    listen: ":1882"
    listen-tls: ":8882"
    public-address: "example.com:8882"
    public-tls-address: "example.com:8882"
```

### Task 5: Gateway Connection Stats

**Files**:
- `api/ttn/lorawan/v3/gatewayserver.proto:111`

**Procedure**:
```bash
# Single gateway
GET /gs/gateways/{gateway_id}/connection/stats

# Batch (up to 100)
POST /gs/gateways/connection/stats
{
  "gateway_ids": [
    {"gateway_id": "gateway-1"},
    {"gateway_id": "gateway-2"}
  ]
}
```

**Response**:
```json
{
  "connected_at": "2025-01-20T10:00:00Z",
  "disconnected_at": null,
  "protocol": "udp",
  "last_status_received_at": "2025-01-20T12:00:00Z",
  "last_status": {...},
  "last_uplink_received_at": "2025-01-20T12:01:00Z",
  "uplink_count": 1523,
  "last_downlink_received_at": "2025-01-20T11:55:00Z",
  "downlink_count": 42,
  "round_trip_times": {
    "min": "10ms",
    "max": "150ms",
    "median": "45ms",
    "count": 100
  }
}
```

### Task 6: Antenna Configuration

**Files**:
- `api/ttn/lorawan/v3/gateway.proto`
- `api/ttn/lorawan/v3/metadata.proto`

**Procedure**:
```bash
PUT /gateways/{gateway_id}
{
  "gateway": {
    "ids": {"gateway_id": "my-gateway"},
    "antennas": [
      {
        "gain": 5.0,
        "location": {
          "latitude": 52.3676,
          "longitude": 4.9041,
          "altitude": 25,
          "accuracy": 10,
          "source": "SOURCE_REGISTRY"
        },
        "placement": "PLACEMENT_OUTDOOR"
      }
    ]
  },
  "field_mask": {"paths": ["antennas"]}
}
```

**Antenna Placement Options**:
- `PLACEMENT_UNKNOWN`
- `PLACEMENT_INDOOR`
- `PLACEMENT_OUTDOOR`

**Location Sources**:
- `SOURCE_UNKNOWN`
- `SOURCE_GPS`
- `SOURCE_REGISTRY`
- `SOURCE_IP_GEOLOCATION`
- `SOURCE_WIFI_RSSI_GEOLOCATION`
- `SOURCE_BT_RSSI_GEOLOCATION`
- `SOURCE_LORA_RSSI_GEOLOCATION`
- `SOURCE_LORA_TDOA_GEOLOCATION`
- `SOURCE_COMBINED_GEOLOCATION`

## Code Patterns

### Gateway Identifier Structure
```go
// pkg/ttnpb/identifiers.go
type GatewayIdentifiers struct {
    GatewayId string   // unique ID
    Eui       []byte   // 8-byte EUI (optional)
}
```

### Frontend Interface
```go
// pkg/gatewayserver/io/io.go
type Frontend interface {
    // Protocol returns the protocol used
    Protocol() string
    // SupportsDownlinkClaim reports whether this frontend supports downlink claims
    SupportsDownlinkClaim() bool
}
```

### Connection State
```go
// pkg/gatewayserver/io/io.go
type Connection interface {
    Context() context.Context
    Frontend() Frontend
    GatewayIdentifiers() *ttnpb.GatewayIdentifiers

    // Send sends a downlink message
    SendDown(down *ttnpb.DownlinkMessage) error

    // Receive receives an uplink message
    RecvUp() (*ttnpb.GatewayUplinkMessage, error)

    // Stats returns connection statistics
    Stats() (stats *ttnpb.GatewayConnectionStats, paths []string)
}
```

### Uplink Token
```go
// pkg/gatewayserver/io/uplink_token.go
// Token encodes gateway info for routing downlinks
type UplinkToken struct {
    GatewayIdentifiers *ttnpb.GatewayIdentifiers
    AntennaIndex       uint32
    Timestamp          uint32
    ConcentratorTime   int64
}
```

## Configuration Reference

### Gateway Server Config
```yaml
gs:
  # General
  require-registered-gateways: true
  forward-status-messages: true
  forward-statistics: true

  # UDP Packet Forwarder
  udp:
    listeners:
      - ":1700"
    schedule-late-time: 800ms
    cone-schedule-timeout: 30s
    connection-expired: 2m
    connection-error-limit: 100
    downlink-path-expires: 15s
    rate-limiting:
      enable: true
      messages: 10
      messages-size: 10000
      messages-jitter: 0.1

  # BasicStation
  basic-station:
    listen: ":8887"
    listen-tls: ":8887"
    use-traffic-tls-address: true
    allow-unauthenticated: false

  # MQTT
  mqtt:
    listen: ":1882"
    listen-tls: ":8882"
    public-address: "localhost:1882"
    public-tls-address: "localhost:8882"

  # MQTT V2 (legacy TTN v2)
  mqtt-v2:
    listen: ":1881"
    listen-tls: ":8881"
```

### Frequency Plans
```yaml
# data/lorawan-frequency-plans/

# Europe
EU_863_870_TTN
EU_863_870

# US
US_902_928_FSB_1
US_902_928_FSB_2
US_902_928

# Asia
AS_923
AS_923_2
AS_923_3
AS_923_4

# Australia
AU_915_928_FSB_1
AU_915_928_FSB_2

# See full list at: data/lorawan-frequency-plans/
```

## File References

| Kategori | Dosya |
|----------|-------|
| Gateway Proto | `api/ttn/lorawan/v3/gateway.proto` |
| Gateway Server Proto | `api/ttn/lorawan/v3/gatewayserver.proto` |
| Gateway Services Proto | `api/ttn/lorawan/v3/gateway_services.proto` |
| IO Interface | `pkg/gatewayserver/io/io.go` |
| UDP Frontend | `pkg/gatewayserver/io/udp/udp.go` |
| UDP Config | `pkg/gatewayserver/io/udp/config.go` |
| UDP Firewall | `pkg/gatewayserver/io/udp/firewall.go` |
| BasicStation Frontend | `pkg/gatewayserver/io/semtechws/ws.go` |
| LNS Messages | `pkg/gatewayserver/io/semtechws/lbslns/messages.go` |
| MQTT Frontend | `pkg/gatewayserver/io/mqtt/mqtt.go` |
| MQTT Topics | `pkg/gatewayserver/io/mqtt/topics/` |
| gRPC Frontend | `pkg/gatewayserver/io/grpc/grpc.go` |
| TTI Gateway | `pkg/gatewayserver/io/ttigw/ttigw.go` |
| Frequency Plans | `data/lorawan-frequency-plans/` |

## Troubleshooting

### Gateway Bağlanmıyor (UDP)
- Port 1700'ün açık olduğunu kontrol et
- Gateway EUI'nin kayıtlı olduğunu doğrula
- `require-registered-gateways: true` ise gateway kayıtlı olmalı
- UDP firewall rate limiting kontrol et

### BasicStation Bağlantı Hatası
- TLS sertifikasının geçerli olduğunu kontrol et
- tc.uri dosyasında doğru URL olduğunu doğrula
- API key'in geçerli olduğunu kontrol et
- WebSocket portuna (8887) erişimi kontrol et

### MQTT Authentication Hatası
- Username formatı: `gateway-id@ttn`
- Password: API key
- TLS kullanılıyorsa doğru portu kullan (8882)

### Downlink Başarısız
- Duty cycle limiti aşılmış olabilir
- Gateway timing offset kontrol et
- Frequency plan uyumunu kontrol et
- `schedule_downlink_late` ayarını kontrol et

### Status Mesajları Gelmiyor
- Gateway stat_interval ayarını kontrol et
- `forward-status-messages: true` olmalı
- Network bağlantısını kontrol et

### Location Güncellenmiyor
- `update_location_from_status: true` olmalı
- Gateway'in GPS'i olmalı
- Status mesajlarında lokasyon bilgisi olmalı
