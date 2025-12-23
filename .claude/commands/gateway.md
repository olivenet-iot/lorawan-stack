# /gateway Komutu

Gateway yönetimi.

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| list | Gateway'leri listele |
| create | Yeni gateway oluştur |
| get | Gateway detayları |
| delete | Gateway sil |
| stats | Bağlantı istatistikleri |
| status | Bağlantı durumu |

## Prosedür

### Gateway Listele

```bash
ttn-lw-cli gateways list
```

JSON formatı:
```bash
ttn-lw-cli gateways list --output-format json
```

### Gateway Oluştur

```bash
ttn-lw-cli gateways create <gateway-id> \
  --gateway-eui <gateway-eui> \
  --frequency-plan-id EU_863_870 \
  --name "Olivenet Gateway 1"
```

Location ile:
```bash
ttn-lw-cli gateways create <gateway-id> \
  --gateway-eui <gateway-eui> \
  --frequency-plan-id EU_863_870 \
  --name "Olivenet Gateway 1" \
  --antenna.location.latitude 35.1856 \
  --antenna.location.longitude 33.3823 \
  --antenna.location.altitude 50
```

### Gateway Detayları

```bash
ttn-lw-cli gateways get <gateway-id>
```

### Bağlantı Durumu

API ile:
```bash
curl -H "Authorization: Bearer $API_KEY" \
  "http://localhost:1885/api/v3/gs/gateways/<gateway-id>/connection/stats"
```

CLI ile:
```bash
ttn-lw-cli gateways get <gateway-id> --gateway-server-address
```

### İstatistikler

```bash
# Gateway Server loglarından
docker compose logs stack 2>&1 | grep "gateway_eui=<EUI>" | tail -50
```

### Gateway Güncelle

Location güncelle:
```bash
ttn-lw-cli gateways set <gateway-id> \
  --antenna.location.latitude 35.1856 \
  --antenna.location.longitude 33.3823
```

### Gateway Sil

```bash
ttn-lw-cli gateways delete <gateway-id>
```

### Gateway Events

```bash
ttn-lw-cli events subscribe --gateway-id <gateway-id>
```

## Frequency Plans

Mevcut frequency plan'ları göster:
```bash
ttn-lw-cli frequency-plans list
```

EU868 için:
- `EU_863_870` - EU 863-870 MHz
- `EU_863_870_TTN` - TTN default

## Gateway Protokolleri

| Protokol | Port | Açıklama |
|----------|------|----------|
| UDP Packet Forwarder | 1700/UDP | Legacy protocol |
| BasicStation | 8887/WSS | Modern protocol |
| MQTT | 1883/TCP | MQTT gateway |

### UDP Packet Forwarder Bağlantısı

```bash
# Bağlantı testi
nc -uvz localhost 1700
```

### BasicStation Bağlantısı

Gateway config:
```json
{
  "uri": "wss://lora.olivenet.com:8887"
}
```

## Örnek Çıktılar

### Gateway List

```
ID              Name                EUI                 Status
gw-001          Olivenet GW 1       AA555A0000000001    Connected
gw-002          Olivenet GW 2       AA555A0000000002    Disconnected
```

### Gateway Stats

```json
{
  "connected_at": "2025-01-22T10:00:00Z",
  "last_uplink_at": "2025-01-22T12:34:56Z",
  "uplink_count": 12345,
  "downlink_count": 234,
  "round_trip_times": {
    "min": "45ms",
    "max": "120ms",
    "median": "67ms"
  }
}
```

## Troubleshooting

### Gateway bağlanamıyor

1. EUI doğru mu?
2. Port 1700 açık mı?
3. Frequency plan uyumlu mu?

```bash
# Logları kontrol et
docker compose logs stack 2>&1 | grep "gs:" | grep -i error
```

### Uplink alınmıyor

1. Antenna bağlı mı?
2. Device frequency doğru mu?
3. RSSI/SNR yeterli mi?

## İlgili Skill

- `@gateway-management` - Detaylı gateway yönetimi

## İlgili Komutlar

- `/device` - Device yönetimi
- `/simulate` - Gateway simülasyonu
- `/test gateway` - Gateway bağlantı testi
