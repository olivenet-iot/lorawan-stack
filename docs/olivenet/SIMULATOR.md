# LoRaWAN Simulator - Kullanım Rehberi

Bu dokümantasyon, Olivenet TTS için geliştirilen LoRaWAN simulator araçlarını açıklar.

## Genel Bakış

Simulator, gerçek gateway ve device olmadan The Things Stack'i test etmek için kullanılır. Python tabanlıdır ve şu özellikleri destekler:

- **Gateway Simulator**: Semtech UDP Packet Forwarder protokolü
- **Device Simulator**: OTAA/ABP cihaz simülasyonu
- **Traffic Generator**: 5000+ cihaz yük testi
- **Join Tester**: OTAA join akışı analizi

## Dizin Yapısı

```
deploy/olivenet/simulator/
├── README.md                    # Hızlı başlangıç
├── requirements.txt             # Python bağımlılıkları
├── config.yml                   # Konfigürasyon
├── lib/
│   ├── __init__.py
│   ├── lorawan_crypto.py        # LoRaWAN kriptografi
│   ├── packet_forwarder.py      # Semtech UDP protokolü
│   ├── device.py                # Virtual device
│   └── gateway.py               # Virtual gateway
├── gateway_simulator.py         # Gateway simulator
├── device_simulator.py          # Device simulator
├── traffic_generator.py         # Yük testi
├── join_tester.py               # Join analizi
├── scenarios/                   # Test senaryoları
│   ├── single_device.yml
│   ├── multi_device.yml
│   ├── join_storm.yml
│   ├── sustained_traffic.yml
│   └── stress_test.yml
└── results/                     # Test sonuçları
```

## Kurulum

```bash
cd deploy/olivenet/simulator

# Virtual environment
python3 -m venv venv
source venv/bin/activate

# Bağımlılıklar
pip install -r requirements.txt
```

## Konfigürasyon

### config.yml

```yaml
stack:
  host: "localhost"              # TTS sunucu
  gateway_udp_port: 1700         # Gateway UDP portu

gateway:
  eui: "AA555A0000000001"        # Gateway EUI
  frequency_plan: "EU_863_870"   # Frekans planı
  location:
    latitude: 35.1856            # North Cyprus
    longitude: 33.3823
    altitude: 50

device:
  dev_eui_prefix: "70B3D57ED0"   # DevEUI prefix
  join_eui: "0000000000000000"   # JoinEUI
  lorawan_version: "1.0.3"       # LoRaWAN version

simulation:
  uplink_interval: 60            # Uplink aralığı (saniye)
  data_rate: 5                   # SF7BW125
```

### Yerel Konfigürasyon

Production değerleri için `config.local.yml` oluşturun:

```bash
cp config.yml config.local.yml
nano config.local.yml
```

## Araçlar

### Gateway Simulator

Virtual gateway bağlantısı:

```bash
# Bağlantı testi
python gateway_simulator.py --test-only

# Interactive mod
python gateway_simulator.py --interactive

# Özel ayarlar
python gateway_simulator.py \
  --eui AA555A0000000099 \
  --server lora.olivenet.com \
  --port 1700
```

**Özellikler:**
- Semtech UDP Packet Forwarder protokolü
- PULL_DATA keepalive (30s interval)
- Downlink alma ve loglama
- Interactive uplink injection

### Device Simulator

Virtual device OTAA/ABP:

```bash
# OTAA join + uplink
python device_simulator.py \
  --dev-eui 70B3D57ED0000001 \
  --app-key 00112233445566778899AABBCCDDEEFF \
  --uplinks 5

# Scenario ile
python device_simulator.py --scenario scenarios/single_device.yml

# ABP
python device_simulator.py \
  --abp \
  --dev-addr 260B1234 \
  --nwk-s-key 00112233445566778899AABBCCDDEEFF \
  --app-s-key FFEEDDCCBBAA00998877665544332211
```

### Join Tester

Detaylı OTAA join analizi:

```bash
python join_tester.py \
  --dev-eui 70B3D57ED0000001 \
  --app-key 00112233445566778899AABBCCDDEEFF
```

**Çıktı:**
- Join Request detayları (DevNonce, MIC)
- Join Accept işleme
- Session key derivation
- Timing analizi

### Traffic Generator

Yük testi:

```bash
# Temel test
python traffic_generator.py \
  --devices 100 \
  --rate 10 \
  --duration 300

# Stress test
python traffic_generator.py --scenario scenarios/stress_test.yml
```

**Özellikler:**
- Asyncio tabanlı paralel işlem
- Memory-efficient (5000+ device)
- Progress bar
- Detaylı istatistikler

## Senaryolar

### single_device.yml
- Amaç: Temel fonksiyonalite testi
- 1 device, OTAA join, 5 uplink
- Kullanım: Hızlı smoke test

### multi_device.yml
- Amaç: Çoklu device testi
- 10 device paralel
- Kullanım: Concurrent device handling

### join_storm.yml
- Amaç: Join Server stress test
- 100 device aynı anda join
- Kullanım: Join capacity testi

### sustained_traffic.yml
- Amaç: Sürdürülebilirlik testi
- 50 device, 5 dakika sürekli traffic
- Kullanım: Stability testi

### stress_test.yml
- Amaç: Production yük simülasyonu
- 5000 device, 10 dakika
- 500 uplink/saniye
- Kullanım: Capacity planning

## API Kullanımı

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
# ... gateway üzerinden gönder ...
device.process_join_accept(join_accept_payload)

# Uplink
uplink = device.build_uplink(port=1, payload=b'\x01\x02\x03')
# ... gateway üzerinden gönder ...
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

async def main():
    await gateway.connect()
    await gateway.send_uplink(phy_payload, radio_params)
    await gateway.disconnect()

asyncio.run(main())
```

### LoRaWAN Crypto

```python
from lib.lorawan_crypto import (
    compute_join_request_mic,
    derive_session_keys,
    encrypt_frm_payload,
)

# MIC hesapla
mic = compute_join_request_mic(
    app_key=bytes(16),
    mhdr=0x00,
    join_eui=bytes(8),
    dev_eui=bytes(8),
    dev_nonce=0x1234,
)

# Session key türet
nwk_s_key, app_s_key = derive_session_keys(
    app_key=bytes(16),
    join_nonce=bytes(3),
    net_id=bytes(3),
    dev_nonce=0x1234,
)
```

## Sorun Giderme

### Gateway bağlanamıyor

1. TTS çalışıyor mu?
```bash
docker compose ps
```

2. Port 1700 açık mı?
```bash
ss -ulnp | grep 1700
nc -uvz localhost 1700
```

3. Config doğru mu?
```bash
cat config.yml | grep -A5 stack
```

### Join başarısız

1. Device TTS'de kayıtlı mı?
```bash
ttn-lw-cli end-devices get <app-id> <device-id>
```

2. AppKey eşleşiyor mu?
```bash
ttn-lw-cli end-devices get <app-id> <device-id> --root-keys
```

3. Join tester çalıştır:
```bash
python join_tester.py --dev-eui <eui> --app-key <key>
```

### Düşük performans

1. Network latency kontrol:
```bash
ping <tts-host>
```

2. TTS resource kullanımı:
```bash
docker stats
```

3. Rate limit azalt:
```bash
python traffic_generator.py --rate 5  # Daha düşük rate
```

## Test Sonuçları

Sonuçlar `results/` dizininde JSON formatında saklanır:

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

## Best Practices

1. **Önce küçük başla**: `single_device.yml` ile test et
2. **Kademeli artır**: 10 → 100 → 1000 → 5000 device
3. **TTS kaynaklarını izle**: `docker stats`
4. **Sonuçları kaydet**: `--output results/test_name.json`
5. **Log'ları kontrol et**: TTS loglarını izle

## İlgili Dokümantasyon

- [OPERATIONS.md](OPERATIONS.md) - Operasyonel prosedürler
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Sorun giderme
- [DEPLOYMENT.md](DEPLOYMENT.md) - Deployment rehberi
