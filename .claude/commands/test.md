# /test Komutu

Sistem testlerini çalıştırır.

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| gateway | Gateway bağlantı testi |
| device | Device join testi |
| api | API endpoint testi |
| all | Tüm testler |
| --scenario FILE | Scenario dosyası ile test |

## Prosedür

### /test gateway

Gateway bağlantı testi:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/simulator
source venv/bin/activate
python gateway_simulator.py --test-only
```

Beklenen çıktı:
- PULL_DATA gönderildi
- PULL_ACK alındı
- Bağlantı başarılı

### /test device

Device join testi:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/simulator
python join_tester.py \
  --dev-eui 70B3D57ED0000001 \
  --app-key 00112233445566778899AABBCCDDEEFF
```

**Not:** Device TTS'de kayıtlı olmalı!

### /test api

API endpoint testi:

```bash
# Health endpoint
curl -s http://localhost:1885/healthz

# Authenticated endpoint (API key gerekli)
curl -s -H "Authorization: Bearer $API_KEY" \
  http://localhost:1885/api/v3/applications
```

### /test all

Sırayla tüm testleri çalıştır:
1. API tests
2. Gateway tests
3. Device tests

## Test Sonuçları

```
Test Results - 2025-01-22 12:34:56

API Tests:
  ✓ Health endpoint (23ms)
  ✓ Auth endpoint (45ms)
  ✓ Device list (89ms)
  ✓ Gateway list (67ms)

Gateway Tests:
  ✓ UDP connection (1.2s)
  ✓ PULL_ACK received (0.8s)

Device Tests:
  ✓ OTAA join (4.5s)
  ✓ Uplink delivered (0.9s)
  ✓ Device visible in Console

Summary: 9/9 tests passed
```

## Senaryo Testi

```bash
python device_simulator.py --scenario scenarios/single_device.yml
```

## Hata Durumları

| Hata | Olası Sebep |
|------|-------------|
| Gateway connection failed | Port 1700 kapalı, TTS çalışmıyor |
| Join timeout | Device kayıtlı değil, AppKey yanlış |
| API 401 | API key geçersiz veya eksik |

## İlgili Komutlar

- `/simulate` - Daha kapsamlı simülasyon
- `/troubleshoot` - Hata analizi
