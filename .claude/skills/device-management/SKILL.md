# Device Management Skill

## Overview

End device lifecycle yönetimi, The Things Stack'in temel operasyonlarından biridir. Bu skill, OTAA/ABP device registration, session management, MAC settings yapılandırması ve device state yönetimi için gerekli bilgileri içerir.

## Key Concepts

### Device Registration Modları

| Mod | Açıklama | Gerekli Keys |
|-----|----------|--------------|
| OTAA | Over-The-Air Activation | AppKey (+ NwkKey for 1.1) |
| ABP | Activation By Personalization | DevAddr, NwkSKey, AppSKey |

### Device State Dağılımı

```
EndDevice
├── Identity Server    → IDs, metadata, attributes
├── Join Server        → Root keys (AppKey, NwkKey), claimed status
├── Network Server     → MAC state, session, frame counters
└── Application Server → Formatters, locations, integrations
```

### Veri Yapıları

**Session** (`api/ttn/lorawan/v3/end_device.proto:38`):
```protobuf
message Session {
  bytes dev_addr = 2;           // 4 bytes
  SessionKeys keys = 3;         // Session keys
  uint32 last_f_cnt_up = 4;     // Uplink frame counter
  uint32 last_n_f_cnt_down = 5; // Network downlink counter
  uint32 last_a_f_cnt_down = 6; // Application downlink counter
  Timestamp started_at = 8;     // Session start time
  repeated ApplicationDownlink queued_application_downlinks = 9;
}
```

**RootKeys** (`api/ttn/lorawan/v3/keys.proto:64`):
```protobuf
message RootKeys {
  string root_key_id = 1;     // JS-issued identifier
  KeyEnvelope app_key = 2;    // Application Key (128-bit)
  KeyEnvelope nwk_key = 3;    // Network Key (128-bit, LoRaWAN 1.1)
}
```

**SessionKeys** (`api/ttn/lorawan/v3/keys.proto:79`):
```protobuf
message SessionKeys {
  bytes session_key_id = 1;       // JS-issued identifier
  KeyEnvelope f_nwk_s_int_key = 2; // Forwarding NwkSIntKey
  KeyEnvelope s_nwk_s_int_key = 3; // Serving NwkSIntKey
  KeyEnvelope nwk_s_enc_key = 4;   // NwkSEncKey
  KeyEnvelope app_s_key = 5;       // AppSKey
}
```

## Common Tasks

### Task 1: OTAA Device Registration

**Files**:
- `api/ttn/lorawan/v3/end_device_services.proto:37`
- `api/ttn/lorawan/v3/joinserver.proto`
- `api/ttn/lorawan/v3/networkserver.proto:141`

**Procedure**:

1. **Identity Server'da oluştur**:
```bash
POST /applications/{app_id}/devices
{
  "end_device": {
    "ids": {
      "device_id": "my-otaa-device",
      "dev_eui": "0004A30B001C0530",
      "join_eui": "70B3D57ED0000000"
    },
    "name": "My OTAA Device",
    "lorawan_version": "MAC_V1_0_3",
    "lorawan_phy_version": "PHY_V1_0_3_REV_A"
  }
}
```

2. **Join Server'da root keys ayarla**:
```bash
PUT /js/applications/{app_id}/devices/{device_id}
{
  "end_device": {
    "ids": {...},
    "root_keys": {
      "app_key": {
        "key": "0123456789ABCDEF0123456789ABCDEF"
      }
    }
  },
  "field_mask": {"paths": ["root_keys.app_key"]}
}
```

3. **Network Server'da kaydet**:
```bash
PUT /ns/applications/{app_id}/devices/{device_id}
{
  "end_device": {
    "ids": {...},
    "frequency_plan_id": "EU_863_870_TTN",
    "lorawan_version": "MAC_V1_0_3",
    "lorawan_phy_version": "PHY_V1_0_3_REV_A",
    "supports_join": true
  },
  "field_mask": {"paths": [
    "frequency_plan_id",
    "lorawan_version",
    "lorawan_phy_version",
    "supports_join"
  ]}
}
```

4. **Application Server'da kaydet**:
```bash
PUT /as/applications/{app_id}/devices/{device_id}
{
  "end_device": {
    "ids": {...}
  },
  "field_mask": {"paths": ["ids"]}
}
```

### Task 2: ABP Device Registration

**Files**:
- `api/ttn/lorawan/v3/end_device.proto:38` (Session)
- `api/ttn/lorawan/v3/networkserver.proto`

**Procedure**:

1. **Identity Server'da oluştur** (OTAA ile aynı)

2. **Network Server'da session ile kaydet**:
```bash
PUT /ns/applications/{app_id}/devices/{device_id}
{
  "end_device": {
    "ids": {...},
    "frequency_plan_id": "EU_863_870_TTN",
    "lorawan_version": "MAC_V1_0_3",
    "lorawan_phy_version": "PHY_V1_0_3_REV_A",
    "supports_join": false,
    "session": {
      "dev_addr": "260BABCD",
      "keys": {
        "f_nwk_s_int_key": {"key": "..."},
        "app_s_key": {"key": "..."}
      }
    }
  },
  "field_mask": {"paths": [
    "frequency_plan_id",
    "lorawan_version",
    "lorawan_phy_version",
    "supports_join",
    "session.dev_addr",
    "session.keys"
  ]}
}
```

3. **Application Server'da AppSKey ile kaydet**:
```bash
PUT /as/applications/{app_id}/devices/{device_id}
{
  "end_device": {
    "ids": {...},
    "session": {
      "dev_addr": "260BABCD",
      "keys": {
        "app_s_key": {"key": "..."}
      }
    }
  },
  "field_mask": {"paths": ["session.dev_addr", "session.keys.app_s_key"]}
}
```

### Task 3: MAC Settings Yapılandırma

**Files**:
- `api/ttn/lorawan/v3/end_device.proto:564` (MACSettings)
- `pkg/networkserver/mac/` (MAC command implementations)

**Key MACSettings Fields**:
```yaml
mac_settings:
  # RX Windows
  rx1_delay: RX_DELAY_1           # 1-15 seconds
  rx1_data_rate_offset: 0         # 0-7
  rx2_data_rate_index: DATA_RATE_0
  rx2_frequency: 869525000        # Hz

  # Class B
  class_b_timeout: 60s
  ping_slot_periodicity: PING_EVERY_4S
  ping_slot_data_rate_index: DATA_RATE_3
  ping_slot_frequency: 869525000

  # Class C
  class_c_timeout: 60s

  # ADR
  adr:
    mode:
      dynamic:
        margin: 15.0              # dB
        min_data_rate_index: DATA_RATE_0
        max_data_rate_index: DATA_RATE_5
        min_nb_trans: 1
        max_nb_trans: 3

  # Frame Counters
  resets_f_cnt: false
  supports_32_bit_f_cnt: true
```

**Update Procedure**:
```bash
PUT /ns/applications/{app_id}/devices/{device_id}
{
  "end_device": {
    "ids": {...},
    "mac_settings": {
      "rx1_delay": "RX_DELAY_1",
      "adr": {
        "mode": {
          "dynamic": {
            "margin": 15.0
          }
        }
      }
    }
  },
  "field_mask": {"paths": [
    "mac_settings.rx1_delay",
    "mac_settings.adr"
  ]}
}
```

### Task 4: Device Silme (Sıralı)

**Procedure** (ters sırada silinmeli):

1. **Application Server'dan sil**:
```bash
DELETE /as/applications/{app_id}/devices/{device_id}
```

2. **Network Server'dan sil**:
```bash
DELETE /ns/applications/{app_id}/devices/{device_id}
```

3. **Join Server'dan sil** (OTAA ise):
```bash
DELETE /js/applications/{app_id}/devices/{device_id}
```

4. **Identity Server'dan sil**:
```bash
DELETE /applications/{app_id}/devices/{device_id}
```

### Task 5: Device State Sorgulama

**Files**:
- `pkg/networkserver/redis/` (device state storage)

**Procedure**:
```bash
# Full device with session info
GET /applications/{app_id}/devices/{device_id}?field_mask=name,session,mac_state,pending_session

# Network Server'dan aktif session
GET /ns/applications/{app_id}/devices/{device_id}?field_mask=session,mac_state
```

**Önemli Field Paths**:
- `session` - Aktif session (DevAddr, keys, frame counters)
- `pending_session` - Bekleyen OTAA session (join accept sonrası)
- `mac_state` - MAC layer durumu (current parameters)
- `mac_settings` - Yapılandırılmış MAC settings

## Code Patterns

### Device Identifier Structure
```go
// pkg/ttnpb/identifiers.go
type EndDeviceIdentifiers struct {
    DeviceId       string
    ApplicationIds *ApplicationIdentifiers
    DevEui         []byte  // 8 bytes
    JoinEui        []byte  // 8 bytes (OTAA only)
    DevAddr        []byte  // 4 bytes (session only)
}
```

### Redis Key Patterns (Network Server)
```
# Device by UID
ns:uid:{application-id}:{device-id}

# Device by DevAddr (for uplink routing)
ns:addr:{dev-addr}:current  → device UID

# Device by EUI (for join routing)
ns:eui:{join-eui}:{dev-eui} → device UID
```

### Device Lookup Flow
```go
// pkg/networkserver/grpc_gsns.go
// 1. Uplink geldiğinde DevAddr ile device bulunur
// 2. EUI ile join request routing
// 3. UID ile direct lookup
```

## Configuration Reference

### LoRaWAN Versions
```yaml
# lorawan_version values:
MAC_V1_0:     "LoRaWAN 1.0"
MAC_V1_0_1:   "LoRaWAN 1.0.1"
MAC_V1_0_2:   "LoRaWAN 1.0.2"
MAC_V1_0_3:   "LoRaWAN 1.0.3"
MAC_V1_0_4:   "LoRaWAN 1.0.4"
MAC_V1_1:     "LoRaWAN 1.1"

# lorawan_phy_version values:
PHY_V1_0:       "RP001 1.0"
PHY_V1_0_1:     "RP001 1.0.1"
PHY_V1_0_2_REV_A: "RP001 1.0.2 Rev A"
PHY_V1_0_2_REV_B: "RP001 1.0.2 Rev B"
PHY_V1_0_3_REV_A: "RP001 1.0.3 Rev A"
PHY_V1_1_REV_A:   "RP001 1.1 Rev A"
PHY_V1_1_REV_B:   "RP001 1.1 Rev B"
```

### Frequency Plans
```yaml
# Common EU frequency plans:
EU_863_870_TTN
EU_863_870

# Common US frequency plans:
US_902_928_FSB_1
US_902_928_FSB_2

# See: data/lorawan-frequency-plans/
```

### Device Classes
```yaml
supports_class_b: false  # Class B (beacon)
supports_class_c: false  # Class C (continuous RX)
# Default: Class A (all devices)
```

## File References

| Kategori | Dosya |
|----------|-------|
| Device Proto | `api/ttn/lorawan/v3/end_device.proto` |
| Keys Proto | `api/ttn/lorawan/v3/keys.proto` |
| Services Proto | `api/ttn/lorawan/v3/end_device_services.proto` |
| NS Device Registry | `api/ttn/lorawan/v3/networkserver.proto:141` |
| AS Device Registry | `api/ttn/lorawan/v3/applicationserver.proto` |
| JS Device Registry | `api/ttn/lorawan/v3/joinserver.proto` |
| NS Redis Storage | `pkg/networkserver/redis/` |
| JS Redis Storage | `pkg/joinserver/redis/` |
| Frequency Plans | `data/lorawan-frequency-plans/` |

## Troubleshooting

### Join Request Başarısız
- JoinEUI ve DevEUI doğruluğunu kontrol et
- AppKey'in Join Server'da kayıtlı olduğunu doğrula
- Frequency plan'ın gateway ile uyumlu olduğunu kontrol et
- `supports_join: true` olmalı

### Session Kayboldu
- ABP device'da session field'larının tüm component'larda kayıtlı olduğunu kontrol et
- Frame counter'ların sıfırlanıp sıfırlanmadığını kontrol et (`resets_f_cnt`)
- DevAddr collision olup olmadığını kontrol et

### Frame Counter Mismatch
- `resets_f_cnt: true` ise her power cycle'da counter sıfırlanır
- 32-bit counter desteği: `supports_32_bit_f_cnt`
- ABP'de counter'lar manuel resetlenebilir

### MAC State Bozuk
- Device'ı NS'den silip tekrar kaydet
- OTAA device için rejoin tetikle
- `mac_state` field mask ile durumu kontrol et

### Downlink Queue Dolu
- `session.queued_application_downlinks` kontrol et
- Queue'yu temizle: `DownlinkQueueReplace` with empty list
- Class A device'lar sadece uplink sonrası downlink alabilir
