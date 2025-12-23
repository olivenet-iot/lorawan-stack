# LoRaWAN Simulator - Olivenet TTS Test Suite

Gerçek gateway ve device olmadan The Things Stack'i test etmek için araçlar.

## Özellikler

- **Gateway Simulator**: UDP Packet Forwarder protokolü ile sanal gateway
- **Device Simulator**: OTAA/ABP destekli sanal LoRaWAN cihaz
- **Traffic Generator**: Yük testi için 5000+ cihaz simülasyonu
- **Join Tester**: OTAA join akışı detaylı analizi
- **Scenario-based Testing**: YAML dosyaları ile test senaryoları

## Kurulum

```bash
cd deploy/olivenet/simulator

# Virtual environment oluştur
python3 -m venv venv
source venv/bin/activate

# Bağımlılıkları yükle
pip install -r requirements.txt
```

## Hızlı Başlangıç

### 1. Config'i Düzenle

```bash
cp config.yml config.local.yml
nano config.local.yml
```

Minimum gerekli ayarlar:
- `stack.host`: TTS sunucu adresi
- `stack.gateway_udp_port`: Gateway UDP portu (varsayılan: 1700)

### 2. Gateway Simulator Başlat

```bash
# Basit bağlantı testi
python gateway_simulator.py --test-only

# Interactive mod
python gateway_simulator.py --interactive
```

### 3. Device Simulator ile Test

```bash
# Tek device OTAA join testi
python device_simulator.py \
  --dev-eui 70B3D57ED0000001 \
  --app-key 00112233445566778899AABBCCDDEEFF \
  --uplinks 5

# Senaryo dosyası ile
python device_simulator.py --scenario scenarios/single_device.yml
```

## Araçlar

| Araç | Açıklama |
|------|----------|
| `gateway_simulator.py` | Sanal gateway, UDP Packet Forwarder |
| `device_simulator.py` | Sanal LoRaWAN cihaz (OTAA/ABP) |
| `join_tester.py` | OTAA join akışı detaylı testi |
| `traffic_generator.py` | Yük testi için bulk traffic |

## Senaryolar

| Senaryo | Açıklama | Kullanım |
|---------|----------|----------|
| `single_device.yml` | Tek device join + 5 uplink | Temel test |
| `multi_device.yml` | 10 device paralel test | Çoklu cihaz |
| `join_storm.yml` | 100 device aynı anda join | Join Server stres |
| `sustained_traffic.yml` | 50 device, 5 dk sürekli | Sürdürülebilirlik |
| `stress_test.yml` | 5000 device, 10 dk | Production yük |

## Kullanım Örnekleri

### Gateway Bağlantı Testi

```bash
# Bağlantıyı test et ve çık
python gateway_simulator.py --test-only

# Özel gateway EUI ile
python gateway_simulator.py --eui AA555A0000000099

# Özel sunucu
python gateway_simulator.py --server lora.olivenet.com --port 1700
```

### OTAA Join Testi

```bash
# Detaylı join analizi
python join_tester.py \
  --dev-eui 70B3D57ED0000001 \
  --app-key 00112233445566778899AABBCCDDEEFF
```

Çıktı:
```
OTAA Join Test - DevEUI: 70B3D57ED0000001
============================================================

Step 1: Preparing Join Request
├── DevEUI: 70B3D57ED0000001
├── JoinEUI: 0000000000000000
├── DevNonce: 0x1A2B
├── MIC: 0xAABBCCDD
└── PHY Payload: 00000000000000000001000000D5B370...

Step 2: Sending via Gateway AA555A0000000001
├── Frequency: 868.1 MHz
├── Data Rate: SF7BW125
└── Timestamp: 2025-01-22T12:34:56Z

Step 3: Waiting for Join Accept...
├── RX1 Window (5s): ⏳ Waiting...
✓ Received!
└── Response time: 4.82s

Step 4: Processing Join Accept
├── Decrypted successfully
├── JoinNonce: 0x123456
├── NetID: 0x000013
├── DevAddr: 260B1234
├── DLSettings: 0x00
├── RxDelay: 1
└── ✓ MIC Valid

Step 5: Deriving Session Keys
├── NwkSKey: 11223344556677889900AABBCCDDEEFF
└── AppSKey: FFEEDDCCBBAA00998877665544332211

✓ JOIN SUCCESSFUL
```

### Yük Testi

```bash
# 100 device, 10 uplink/sec, 5 dakika
python traffic_generator.py \
  --devices 100 \
  --rate 10 \
  --duration 300

# 5000 device stres testi
python traffic_generator.py --scenario scenarios/stress_test.yml
```

### ABP Device Testi

```bash
python device_simulator.py \
  --abp \
  --dev-addr 260B1234 \
  --nwk-s-key 00112233445566778899AABBCCDDEEFF \
  --app-s-key FFEEDDCCBBAA00998877665544332211 \
  --uplinks 10
```

## Konfigürasyon

### config.yml Yapısı

```yaml
stack:
  host: "localhost"           # TTS sunucu
  gateway_udp_port: 1700      # Gateway UDP portu

gateway:
  eui: "AA555A0000000001"     # Gateway EUI
  frequency_plan: "EU_863_870"

device:
  dev_eui_prefix: "70B3D57ED0"
  join_eui: "0000000000000000"

simulation:
  uplink_interval: 60         # Saniye
  data_rate: 5                # SF7BW125
```

### Senaryo Dosyası Formatı

```yaml
name: "Test Adı"
description: "Açıklama"

devices:
  - dev_eui: "70B3D57ED0000001"
    join_eui: "0000000000000000"
    app_key: "00112233445566778899AABBCCDDEEFF"
    activation: "OTAA"

test:
  join_timeout: 10
  uplink_count: 5
  uplink_interval: 10

assertions:
  - join_success: true
```

## Çıktılar

Test sonuçları `results/` dizininde JSON formatında saklanır:

```json
{
  "timestamp": "2025-01-22T12:34:56Z",
  "devices_total": 100,
  "devices_joined": 98,
  "join_success_rate": 98.0,
  "uplinks_sent": 4850,
  "uplinks_per_second": 16.2,
  "duration": 300.5,
  "errors": 2
}
```

## Kütüphane API

### VirtualDevice

```python
from lib.device import VirtualDevice

device = VirtualDevice(
    dev_eui=bytes.fromhex('70B3D57ED0000001'),
    join_eui=bytes(8),
    app_key=bytes.fromhex('00112233445566778899AABBCCDDEEFF'),
)

# OTAA Join
join_request = device.build_join_request()
device.process_join_accept(join_accept_payload)

# Uplink
uplink = device.build_uplink(port=1, payload=b'\x01\x02\x03')
```

### VirtualGateway

```python
from lib.gateway import VirtualGateway, GatewayConfig

config = GatewayConfig(
    eui="AA555A0000000001",
    server_host="localhost",
    server_port=1700,
)

gateway = VirtualGateway(config=config)
await gateway.connect()
await gateway.send_uplink(phy_payload, radio_params)
await gateway.disconnect()
```

## Sorun Giderme

### Gateway Bağlanamıyor

1. TTS'in çalıştığından emin olun
2. Port 1700/UDP'nin açık olduğunu kontrol edin
3. Firewall kurallarını kontrol edin

```bash
# Port kontrolü
nc -uvz localhost 1700
```

### Join Başarısız

1. DevEUI ve AppKey'in TTS'de kayıtlı olduğunu kontrol edin
2. Frequency plan uyumluluğunu kontrol edin
3. `join_tester.py` ile detaylı analiz yapın

### Düşük Performans

1. Network latency'yi kontrol edin
2. TTS kaynak kullanımını kontrol edin
3. Rate limit'i azaltın

## Gereksinimler

- Python 3.8+
- pycryptodome (LoRaWAN crypto)
- pyyaml (config parsing)
- colorama (terminal renkleri)
- tqdm (progress bar)
- asyncio (async I/O)

## Lisans

Bu araçlar Olivenet TTS deployment'ı için geliştirilmiştir.
