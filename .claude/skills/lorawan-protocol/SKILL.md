# LoRaWAN Protocol Skill

## Overview

LoRaWAN protokol implementasyonu, The Things Stack'in çekirdeğini oluşturur. Bu skill, MAC commands, class A/B/C operasyonları, uplink/downlink processing, join procedure ve encryption mekanizmalarını kapsar.

## Key Concepts

### Message Types (MType)

| MType | Değer | Açıklama |
|-------|-------|----------|
| JOIN_REQUEST | 0 | OTAA join isteği |
| JOIN_ACCEPT | 1 | Join kabul yanıtı |
| UNCONFIRMED_UP | 2 | Onaysız uplink |
| UNCONFIRMED_DOWN | 3 | Onaysız downlink |
| CONFIRMED_UP | 4 | Onaylı uplink (ACK bekleniyor) |
| CONFIRMED_DOWN | 5 | Onaylı downlink (ACK bekleniyor) |
| REJOIN_REQUEST | 6 | Rejoin isteği (LoRaWAN 1.1) |
| PROPRIETARY | 7 | Proprietary frame |

### LoRaWAN Versions

```protobuf
// api/ttn/lorawan/v3/lorawan.proto:74
enum MACVersion {
  MAC_UNKNOWN = 0;
  MAC_V1_0 = 1;     // LoRaWAN 1.0
  MAC_V1_0_1 = 2;   // LoRaWAN 1.0.1
  MAC_V1_0_2 = 3;   // LoRaWAN 1.0.2
  MAC_V1_1 = 4;     // LoRaWAN 1.1
  MAC_V1_0_3 = 5;   // LoRaWAN 1.0.3
  MAC_V1_0_4 = 6;   // LoRaWAN 1.0.4
}
```

### PHY Versions

```protobuf
// api/ttn/lorawan/v3/lorawan.proto:110
enum PHYVersion {
  PHY_UNKNOWN = 0;
  PHY_V1_0 = 1;           // RP001 1.0
  PHY_V1_0_1 = 2;         // RP001 1.0.1
  PHY_V1_0_2_REV_A = 3;   // RP001 1.0.2 Rev A
  PHY_V1_0_2_REV_B = 4;   // RP001 1.0.2 Rev B
  PHY_V1_0_3_REV_A = 5;   // RP001 1.0.3 Rev A
  PHY_V1_1_REV_A = 6;     // RP001 1.1 Rev A
  PHY_V1_1_REV_B = 7;     // RP001 1.1 Rev B
  RP002_V1_0_0 = 8;       // RP002 1.0.0
  RP002_V1_0_1 = 9;       // RP002 1.0.1
  RP002_V1_0_2 = 10;      // RP002 1.0.2
  RP002_V1_0_3 = 11;      // RP002 1.0.3
  RP002_V1_0_4 = 12;      // RP002 1.0.4
}
```

### Device Classes

| Class | Receive Window | Downlink |
|-------|---------------|----------|
| A | RX1 + RX2 after uplink | Only after uplink |
| B | Scheduled ping slots | At scheduled times |
| C | Continuous RX2 | Anytime (except TX) |

### Message Structure

```
+--------+--------+--------+...+--------+--------+
| MHDR   |     FHDR       ... | FPort  |FRMPayload|
+--------+--------+--------+...+--------+--------+
   1B       7-22B               1B       0-N B

MHDR = MType(3b) | RFU(3b) | Major(2b)
FHDR = DevAddr(4B) | FCtrl(1B) | FCnt(2B) | FOpts(0-15B)
```

## MAC Commands

### Network Server MAC Command Files

`pkg/networkserver/mac/` dizininde 30+ MAC command implementasyonu bulunur:

| Dosya | MAC Command | CID | Açıklama |
|-------|-------------|-----|----------|
| `adr.go` | LinkADR | 0x03 | Adaptive Data Rate |
| `link_adr.go` | LinkADRAns | 0x03 | ADR yanıtı |
| `link_check.go` | LinkCheck | 0x02 | Link quality check |
| `dev_status.go` | DevStatus | 0x06 | Device status request |
| `new_channel.go` | NewChannel | 0x07 | Yeni kanal tanımlama |
| `rx_param_setup.go` | RXParamSetup | 0x05 | RX2 parameters |
| `rx_timing_setup.go` | RXTimingSetup | 0x08 | RX1 delay ayarı |
| `tx_param_setup.go` | TXParamSetup | 0x09 | Max EIRP/dwell time |
| `dl_channel.go` | DLChannel | 0x0A | Downlink channel |
| `duty_cycle.go` | DutyCycle | 0x04 | Duty cycle limit |
| `device_time.go` | DeviceTime | 0x0D | GPS time sync |
| `ping_slot_info.go` | PingSlotInfo | 0x10 | Class B ping slot |
| `ping_slot_channel.go` | PingSlotChannel | 0x11 | Ping slot frequency |
| `beacon_freq.go` | BeaconFreq | 0x13 | Beacon frequency |
| `beacon_timing.go` | BeaconTiming | 0x12 | Beacon timing |
| `device_mode.go` | DeviceMode | 0x20 | Class switching |
| `reset.go` | Reset | 0x01 | Device reset indication |
| `rekey.go` | Rekey | 0x0B | Session key update (1.1) |
| `rejoin_param_setup.go` | RejoinParam | 0x0F | Rejoin parameters |
| `relay_*.go` | Relay commands | 0x40+ | LoRaWAN 2.4 relay |

### ADR Algorithm

**File**: `pkg/networkserver/mac/adr.go`

```go
// ADR calculation factors:
// - SNR margin (default 15 dB)
// - Min/max data rate index
// - Min/max TX power index
// - Min/max NbTrans

// ADR modes:
// - Dynamic: NS optimizes automatically
// - Static: Fixed DR, TXPower, NbTrans
// - Disabled: Device controls ADR
```

**Configuration**:
```yaml
mac_settings:
  adr:
    mode:
      dynamic:
        margin: 15.0              # dB margin
        min_data_rate_index: DATA_RATE_0
        max_data_rate_index: DATA_RATE_5
        min_tx_power_index: 0
        max_tx_power_index: 7
        min_nb_trans: 1
        max_nb_trans: 3
```

## Common Tasks

### Task 1: Join Procedure (OTAA)

**Files**:
- `pkg/joinserver/` (key derivation)
- `pkg/networkserver/grpc_gsns.go` (join handling)
- `api/ttn/lorawan/v3/join.proto`

**Flow**:
```
1. Device sends JOIN_REQUEST
   ├── MHDR: MType=JOIN_REQUEST
   ├── JoinEUI (8 bytes)
   ├── DevEUI (8 bytes)
   ├── DevNonce (2 bytes)
   └── MIC (4 bytes)

2. Network Server validates, forwards to Join Server

3. Join Server:
   ├── Validates MIC with AppKey
   ├── Generates DevAddr
   ├── Derives session keys (NwkSKey, AppSKey)
   └── Returns JOIN_ACCEPT

4. Network Server sends JOIN_ACCEPT
   ├── MHDR: MType=JOIN_ACCEPT
   ├── JoinNonce (3 bytes)
   ├── NetID (3 bytes)
   ├── DevAddr (4 bytes)
   ├── DLSettings (1 byte)
   ├── RXDelay (1 byte)
   ├── CFList (optional, 16 bytes)
   └── MIC (4 bytes)

5. Device activates with new session
```

### Task 2: Uplink Processing

**Files**:
- `pkg/networkserver/grpc_gsns.go:1493` (HandleUplink)
- `pkg/networkserver/grpc_gsns.go:73` (deduplicateUplink)

**Flow**:
```
Gateway → GS → NS HandleUplink
               ├── 1. Deduplicate (same FCnt from multiple gateways)
               ├── 2. Match device by DevAddr
               ├── 3. Verify MIC
               ├── 4. Check frame counter
               ├── 5. Decrypt FRMPayload (if FPort > 0)
               ├── 6. Process FOpts (MAC commands)
               ├── 7. Update device state
               ├── 8. Schedule downlink (if needed)
               └── 9. Forward to Application Server
```

**Deduplication**:
```go
// pkg/networkserver/grpc_gsns.go
// Deduplication window: ~200ms
// Keeps best gateway (highest SNR)
```

### Task 3: Downlink Scheduling

**Files**:
- `pkg/networkserver/downlink.go`
- `pkg/gatewayserver/` (scheduling)

**Class A Downlink**:
```
Uplink received at T0
├── RX1 window: T0 + RX1Delay (default 1s)
│   └── Same channel, configurable DR offset
└── RX2 window: T0 + RX1Delay + 1s
    └── Fixed frequency/DR (region specific)
```

**Class B Downlink**:
```
Ping slots = 2^(7-periodicity) per beacon period
├── PingSlotPeriodicity: 0-7 (128 to 1 slots)
└── Beacon period: 128 seconds
```

**Class C Downlink**:
```
Device always listening on RX2
└── Can receive anytime (except during TX)
```

### Task 4: MAC Command Processing

**Files**:
- `pkg/networkserver/mac/mac.go`
- Individual command files in `pkg/networkserver/mac/`

**Example: LinkCheck**:
```go
// pkg/networkserver/mac/link_check.go
// Device sends LinkCheckReq (no payload)
// NS responds with LinkCheckAns:
// - Margin: SNR - required SNR for demodulation
// - GwCnt: Number of gateways that received uplink
```

**Example: DevStatus**:
```go
// pkg/networkserver/mac/dev_status.go
// NS sends DevStatusReq
// Device responds with DevStatusAns:
// - Battery: 0=external, 1-254=level, 255=unknown
// - Margin: SNR margin
```

### Task 5: Frame Counter Management

**Files**:
- `api/ttn/lorawan/v3/end_device.proto:38` (Session)
- `pkg/networkserver/` (FCnt handling)

**Counter Types**:
```
Session:
├── last_f_cnt_up: Last uplink FCnt
├── last_n_f_cnt_down: Network downlink FCnt
├── last_a_f_cnt_down: Application downlink FCnt
└── last_conf_f_cnt_down: Last confirmed downlink FCnt
```

**Gap Handling**:
```yaml
# Device settings
resets_f_cnt: false        # Device resets on power cycle
supports_32_bit_f_cnt: true # Full 32-bit counter support

# LoRaWAN 1.0.x: Single FCntDown
# LoRaWAN 1.1:   Separate NFCntDown, AFCntDown
```

### Task 6: Encryption

**Key Types**:
```
Root Keys (stored in Join Server):
├── AppKey: Application key (used for JOIN)
└── NwkKey: Network key (LoRaWAN 1.1 only)

Session Keys (derived after JOIN):
├── NwkSKey/FNwkSIntKey: Network session integrity key
├── SNwkSIntKey: Serving network session integrity key (1.1)
├── NwkSEncKey: Network session encryption key (1.1)
└── AppSKey: Application session key
```

**Encryption Layers**:
```
MIC Calculation:
├── LoRaWAN 1.0.x: NwkSKey for all
└── LoRaWAN 1.1: FNwkSIntKey + SNwkSIntKey

Payload Encryption:
├── FPort = 0: NwkSKey (MAC commands)
└── FPort > 0: AppSKey (application data)
```

## Code Patterns

### Uplink Handler Pattern
```go
// pkg/networkserver/grpc_gsns.go:1493
func (ns *NetworkServer) HandleUplink(ctx context.Context, up *ttnpb.UplinkMessage) (*emptypb.Empty, error) {
    // 1. Parse PHY payload
    // 2. Route based on MType
    // 3. For data uplinks: match device, verify, process
    // 4. For join requests: forward to Join Server
}
```

### MAC Command Handler Pattern
```go
// pkg/networkserver/mac/
type Handler func(context.Context, *ttnpb.EndDevice, ...) error

// Each command has:
// - Enqueueing function (NS → Device)
// - Response handler (Device → NS)
```

### Device State Update Pattern
```go
// After processing uplink:
// 1. Update MAC state (current parameters)
// 2. Update session (frame counters)
// 3. Queue pending MAC commands
// 4. Store in Redis
```

## Configuration Reference

### RX Window Settings
```yaml
mac_settings:
  rx1_delay: RX_DELAY_1           # 1-15 seconds
  rx1_data_rate_offset: 0         # 0-7
  rx2_data_rate_index: DATA_RATE_0
  rx2_frequency: 869525000        # Hz
```

### Class B Settings
```yaml
mac_settings:
  class_b_timeout: 60s
  ping_slot_periodicity: PING_EVERY_4S
  ping_slot_data_rate_index: DATA_RATE_3
  ping_slot_frequency: 869525000
  beacon_frequency: 869525000
```

### Class C Settings
```yaml
mac_settings:
  class_c_timeout: 60s
```

### Data Rate Indices (EU868)
```
DATA_RATE_0: SF12/125kHz (250 bps)
DATA_RATE_1: SF11/125kHz (440 bps)
DATA_RATE_2: SF10/125kHz (980 bps)
DATA_RATE_3: SF9/125kHz (1760 bps)
DATA_RATE_4: SF8/125kHz (3125 bps)
DATA_RATE_5: SF7/125kHz (5470 bps)
DATA_RATE_6: SF7/250kHz (11000 bps)
DATA_RATE_7: FSK (50000 bps)
```

## File References

| Kategori | Dosya |
|----------|-------|
| LoRaWAN Proto | `api/ttn/lorawan/v3/lorawan.proto` |
| Messages Proto | `api/ttn/lorawan/v3/messages.proto` |
| Join Proto | `api/ttn/lorawan/v3/join.proto` |
| Regional Proto | `api/ttn/lorawan/v3/regional.proto` |
| MAC Handlers | `pkg/networkserver/mac/` |
| ADR | `pkg/networkserver/mac/adr.go` |
| Link ADR | `pkg/networkserver/mac/link_adr.go` |
| Link Check | `pkg/networkserver/mac/link_check.go` |
| Device Status | `pkg/networkserver/mac/dev_status.go` |
| RX Param Setup | `pkg/networkserver/mac/rx_param_setup.go` |
| Uplink Handler | `pkg/networkserver/grpc_gsns.go:1493` |
| Downlink Handler | `pkg/networkserver/downlink.go` |
| Join Server | `pkg/joinserver/` |
| Frequency Plans | `data/lorawan-frequency-plans/` |

## Troubleshooting

### MIC Verification Failure
- Key mismatch: Doğru root keys/session keys kontrol et
- Frame counter: Counter mismatch olabilir
- Version mismatch: MAC version uyumsuzluğu

### Join Request Başarısız
- JoinEUI/DevEUI formatı kontrol et
- AppKey doğruluğunu kontrol et
- DevNonce tekrarı (replay attack koruması)

### Frame Counter Mismatch
- `resets_f_cnt` ayarını kontrol et
- 16-bit vs 32-bit counter desteği
- Device'ın power cycle yapıp yapmadığını kontrol et

### ADR Çalışmıyor
- `adr.mode` ayarını kontrol et
- Device'ın ADR desteği olmalı
- Yeterli uplink geçmişi gerekli

### Downlink Alınamıyor
- Class A: Uplink sonrası RX window'da olmalı
- Class B: Beacon sync yapılmış olmalı
- Class C: `supports_class_c: true` olmalı
- Duty cycle limiti aşılmış olabilir
