# /simulate Komutu

LoRaWAN simulator'ü çalıştırır.

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| gateway | Gateway simulator |
| device | Device simulator |
| traffic | Traffic generator |
| join | Join tester |
| --scenario FILE | Scenario dosyası |
| --devices N | Device sayısı |
| --duration S | Süre (saniye) |

## Kurulum

Simulator'ü ilk kez kullanmadan önce:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/simulator

# Virtual environment oluştur
python3 -m venv venv
source venv/bin/activate

# Bağımlılıkları yükle
pip install -r requirements.txt
```

## Prosedür

### /simulate gateway

Gateway bağlantı simülasyonu:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/simulator
source venv/bin/activate

# Bağlantı testi
python gateway_simulator.py --test-only

# Interactive mod
python gateway_simulator.py --interactive

# Özel EUI ile
python gateway_simulator.py --eui AA555A0000000099
```

### /simulate device

Device simülasyonu:

```bash
# Tek device OTAA join
python device_simulator.py \
  --dev-eui 70B3D57ED0000001 \
  --app-key 00112233445566778899AABBCCDDEEFF \
  --uplinks 5

# Scenario dosyası ile
python device_simulator.py --scenario scenarios/single_device.yml
```

### /simulate join

Detaylı join analizi:

```bash
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
└── MIC: 0xAABBCCDD

Step 2: Sending via Gateway
├── Frequency: 868.1 MHz
└── Data Rate: SF7BW125

Step 3: Waiting for Join Accept...
✓ Received!
└── Response time: 4.82s

Step 4: Processing Join Accept
├── DevAddr: 260B1234
└── ✓ MIC Valid

Step 5: Deriving Session Keys
├── NwkSKey: 11223344...
└── AppSKey: FFEEDDCC...

✓ JOIN SUCCESSFUL
```

### /simulate traffic

Yük testi:

```bash
# 100 device, 10 uplink/sec, 5 dakika
python traffic_generator.py \
  --devices 100 \
  --rate 10 \
  --duration 300

# Scenario dosyası ile
python traffic_generator.py --scenario scenarios/stress_test.yml

# 5000 device stress test
python traffic_generator.py --scenario scenarios/stress_test.yml
```

Çıktı:
```
Traffic Generator - 100 devices, 10 uplinks/sec
============================================================

Joining: 100%|██████████| 100/100 [00:45<00:00]
  joined: 98, failed: 2

Traffic: 100%|██████████| 300/300 [05:00<00:00]
  uplinks: 3000, rate: 10.0/s

Test Summary
============================================================
Duration:             300.5s
Devices joined:       98/100 (98.0%)
Uplinks sent:         2940
Uplinks/sec:          9.8
Errors:               2
```

## Mevcut Senaryolar

| Senaryo | Açıklama | Kullanım |
|---------|----------|----------|
| `single_device.yml` | Tek device join + uplink | Temel test |
| `multi_device.yml` | 10 device paralel | Çoklu device |
| `join_storm.yml` | 100 device aynı anda | Join stress |
| `sustained_traffic.yml` | 50 device, 5 dk | Sürdürülebilirlik |
| `stress_test.yml` | 5000 device, 10 dk | Production yük |

## Önemli Notlar

⚠️ **DİKKAT:**

1. **Simulator stack'e bağlanır**
   - Stack çalışıyor olmalı
   - Port 1700/UDP açık olmalı

2. **Test device'lar TTS'de kayıtlı olmalı**
   - Simulator otomatik kayıt yapmaz
   - Console'dan veya CLI ile oluşturun

3. **AppKey eşleşmeli**
   - Simulator'deki AppKey = TTS'deki AppKey

4. **Config dosyası**
   - `config.yml` dosyasını düzenleyin
   - Veya `config.local.yml` oluşturun

## Config Örneği

```yaml
# config.yml
stack:
  host: "localhost"
  gateway_udp_port: 1700

gateway:
  eui: "AA555A0000000001"

device:
  dev_eui_prefix: "70B3D57ED0"
  join_eui: "0000000000000000"
```

## Sonuç Dosyaları

Sonuçlar `results/` dizininde saklanır:

```
results/
├── stress_test_20250122_123456.json
├── simulator.log
└── .gitkeep
```

## İlgili Dokümantasyon

- `deploy/olivenet/simulator/README.md` - Detaylı simulator rehberi

## İlgili Komutlar

- `/test` - Temel testler
- `/device` - Device yönetimi (kayıt için)
- `/gateway` - Gateway yönetimi
