# TTS Kurulum Validasyon Rehberi

Bu rehber, The Things Stack kurulumunun dogru calistigini dogrulamak icin adim adim kontroller icerir.

## Hizli Validasyon (2 dakika)

```bash
cd /opt/lorawan-stack/deploy/olivenet

# 1. Health Check
./scripts/health-check.sh

# Beklenen: Status: HEALTHY
```

## Detayli Validasyon Checklist

### 1. Servis Durumu

```bash
# Container'lar calisiyor mu?
docker compose ps

# Beklenen: 3 container (postgres, redis, stack) - healthy
```

| Container | Beklenen Durum |
|-----------|----------------|
| olivenet-postgres | Up (healthy) |
| olivenet-redis | Up (healthy) |
| olivenet-stack | Up (healthy) |

### 2. API Erisimi

```bash
# Health endpoint
curl -s https://YOUR_DOMAIN/healthz | jq .

# Beklenen: {"status":"OK", ...}
```

### 3. Console Erisimi

1. Browser'da ac: `https://YOUR_DOMAIN/console`
2. Admin credentials ile giris yap
3. Dashboard yuklenmelidir

### 4. Gateway Baglantisi (UDP 1700)

```bash
# Simulator ile test
source simulator/activate.sh
python3 gateway_simulator.py --server YOUR_DOMAIN --port 1700 --eui AA555A0000000001 --test-only

# Beklenen: PULL_ACK received
```

### 5. MQTT Baglantisi (Port 8883)

```bash
# Console'dan API key olustur, sonra:
mosquitto_sub -h YOUR_DOMAIN -p 8883 \
  --capath /etc/ssl/certs/ \
  -t "v3/+/devices/+/up" \
  -u "APP_ID" \
  -P "NNSXS.API_KEY..." \
  -C 1 -W 5

# Beklenen: Baglanti basarili (timeout olabilir - veri yoksa normal)
```

### 6. TLS Sertifikasi

```bash
# Sertifika bilgilerini goster
echo | openssl s_client -connect YOUR_DOMAIN:443 -servername YOUR_DOMAIN 2>/dev/null | openssl x509 -noout -subject -dates

# Beklenen: Let's Encrypt sertifikasi, gecerli tarihler
```

### 7. Veritabani Baglantisi

```bash
# PostgreSQL
docker exec olivenet-postgres pg_isready -U ttn

# Beklenen: accepting connections

# Redis
docker exec olivenet-redis redis-cli ping

# Beklenen: PONG
```

### 8. Port Kontrolu

```bash
# Acik portlari kontrol et
docker exec olivenet-stack netstat -tlnp | grep -E "1700|1882|1883|8882|8883|8885|8887"
```

| Port | Protokol | Kullanim | Kontrol |
|------|----------|----------|---------|
| 1700/UDP | Semtech UDP | Gateway | |
| 1882 | MQTT | GS Gateway | |
| 8882 | MQTTS | GS Gateway TLS | |
| 1883 | MQTT | AS Application | |
| 8883 | MQTTS | AS Application TLS | |
| 8885 | HTTPS | Console/API | |
| 8887 | WSS | BasicStation | |

## Sorun Giderme

### Container baslamiyor

```bash
docker logs olivenet-stack --tail 100
```

### OAuth login hatasi

```bash
# Grants kontrolu
docker exec olivenet-postgres psql -U ttn -d ttn_lorawan -c \
  "SELECT client_id, grants FROM clients WHERE client_id = 'console';"

# Beklenen: grants = {0,2}
```

### Gateway baglanmiyor

```bash
# UDP port kontrolu
nc -vzu YOUR_DOMAIN 1700

# Firewall kontrolu
sudo ufw status
```

## Otomatik Validasyon Script'i

```bash
./scripts/validate.sh
```

Bu script tum kontrolleri otomatik yapar ve rapor olusturur.

## Kontrol Detaylari

### Container Health Check

Her container icin health check tanimlanmistir:

- **PostgreSQL**: `pg_isready -U ttn`
- **Redis**: `redis-cli ping`
- **Stack**: `/healthz` endpoint

### Network Connectivity

Stack'in dis dunyaya erisimi icin:

```bash
# DNS cozumlemesi
docker exec olivenet-stack nslookup google.com

# HTTP erisimi
docker exec olivenet-stack curl -s https://www.thethingsindustries.com/docs/
```

### Log Analizi

Kritik hatalari bulmak icin:

```bash
# Son 1 saatteki hatalar
docker logs olivenet-stack --since 1h 2>&1 | grep -i error

# Join request sorunlari
docker logs olivenet-stack --since 1h 2>&1 | grep -i "join"
```

## Performans Metrikleri

### Veritabani Baglanti Sayisi

```bash
docker exec olivenet-postgres psql -U ttn -d ttn_lorawan -c \
  "SELECT count(*) FROM pg_stat_activity;"
```

Normal: < 50 baglanti
Uyari: 50-180 baglanti
Kritik: > 180 baglanti

### Redis Bellek Kullanimi

```bash
docker exec olivenet-redis redis-cli INFO memory | grep used_memory_human
```

Normal: < 1GB
Uyari: 1-4GB
Kritik: > 4GB

### Disk Kullanimi

```bash
df -h /var/lib/docker
```

Normal: < 80%
Uyari: 80-95%
Kritik: > 95%
