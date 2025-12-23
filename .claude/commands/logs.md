# /logs Komutu

Log görüntüleme ve analizi.

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| stack | TTS stack logları |
| postgres | PostgreSQL logları |
| redis | Redis logları |
| all | Tüm loglar |
| --tail N | Son N satır |
| --since TIME | Belirli zamandan itibaren |
| --follow | Canlı takip |
| --filter TEXT | Filtrele |

## Prosedür

### Stack Logları

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet
docker compose logs stack --tail 100
```

Canlı takip:
```bash
docker compose logs -f stack
```

### Component Filtreleme

```bash
# Gateway Server logları
docker compose logs stack 2>&1 | grep "gs:"

# Network Server logları
docker compose logs stack 2>&1 | grep "ns:"

# Join Server logları
docker compose logs stack 2>&1 | grep "js:"

# Application Server logları
docker compose logs stack 2>&1 | grep "as:"

# Identity Server logları
docker compose logs stack 2>&1 | grep "is:"
```

### Device/Gateway Filtreleme

```bash
# Belirli device
docker compose logs stack 2>&1 | grep "dev_eui=70B3D57ED0000001"

# Belirli gateway
docker compose logs stack 2>&1 | grep "gateway_eui=AA555A0000000001"

# Belirli application
docker compose logs stack 2>&1 | grep "application_id=my-app"
```

### Error Filtreleme

```bash
# Sadece error'lar
docker compose logs stack 2>&1 | grep -i error

# Error ve warning
docker compose logs stack 2>&1 | grep -iE "error|warn"
```

### Zaman Filtreleme

```bash
# Son 1 saat
docker compose logs stack --since 1h

# Belirli tarihten
docker compose logs stack --since 2025-01-22T10:00:00
```

### PostgreSQL Logları

```bash
docker compose logs postgres --tail 50
```

### Redis Logları

```bash
docker compose logs redis --tail 50
```

## Log Formatı

TTS JSON formatında log üretir:

```json
{
  "level": "info",
  "msg": "Received uplink",
  "namespace": "ns",
  "dev_eui": "70B3D57ED0000001",
  "f_cnt": 123,
  "time": "2025-01-22T12:34:56Z"
}
```

## Log Analizi

### Uplink sayısı (son 1 saat)

```bash
docker compose logs stack --since 1h 2>&1 | grep "Received uplink" | wc -l
```

### Join request sayısı

```bash
docker compose logs stack --since 1h 2>&1 | grep "Join-request" | wc -l
```

### En çok hata veren device

```bash
docker compose logs stack 2>&1 | grep -i error | grep -oP 'dev_eui=\K[A-F0-9]+' | sort | uniq -c | sort -rn | head
```

## Log Rotation

Loglar Docker tarafından yönetilir:

```yaml
# docker-compose.yml
services:
  stack:
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "3"
```

## İlgili Komutlar

- `/troubleshoot` - Log analizi ile sorun giderme
- `/status` - Sistem durumu

## İlgili Skill

- `@troubleshooting` - Log pattern'leri ve analiz
