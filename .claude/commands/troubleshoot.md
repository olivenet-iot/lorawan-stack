# /troubleshoot Komutu

Sorun giderme rehberi ve diagnostik.

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| gateway | Gateway bağlantı sorunları |
| device | Device sorunları (join, uplink) |
| join | Join failure analizi |
| uplink | Uplink sorunları |
| downlink | Downlink sorunları |
| webhook | Webhook sorunları |
| performance | Performans sorunları |

## Genel Diagnostik

Önce genel durum kontrolü:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/scripts
./health-check.sh
```

## Gateway Sorunları

### Gateway bağlanamıyor

1. Port 1700 açık mı?
```bash
ss -ulnp | grep 1700
nc -uvz localhost 1700
```

2. Gateway Server logları:
```bash
docker compose logs stack 2>&1 | grep "gs:" | tail -50
```

3. Firewall kontrolü:
```bash
sudo ufw status
sudo iptables -L -n | grep 1700
```

4. Gateway EUI doğru mu?
```bash
# Console'dan veya CLI ile kontrol
ttn-lw-cli gateways get <gateway-id>
```

### Gateway connected ama traffic yok

1. Frequency plan uyumlu mu?
2. Gateway location set mi?
3. Antenna bağlı mı? (fiziksel)

## Join Sorunları

### Join request görünmüyor

1. Gateway bağlı mı?
2. Device frequency plan doğru mu?
3. Device uplink gönderebiliyor mu?

### Join accept alınamıyor

1. AppKey doğru mu?
```bash
# Console'dan kontrol et
ttn-lw-cli end-devices get <app-id> <dev-id> --root-keys
```

2. DevNonce replay mı?
```bash
docker compose logs stack 2>&1 | grep "Join-request" | grep <dev_eui>
```

3. Join Server logları:
```bash
docker compose logs stack 2>&1 | grep "js:" | tail -50
```

## Uplink Sorunları

### Uplink görünmüyor

1. Device session aktif mi?
2. Frame counter reset mi oldu?
3. MIC verification failure mı?

```bash
docker compose logs stack 2>&1 | grep <dev_eui> | tail -50
```

### Uplink geliyor ama Application Server'a ulaşmıyor

1. Device routing doğru mu?
2. Application Server logları:
```bash
docker compose logs stack 2>&1 | grep "as:" | tail -50
```

## Downlink Sorunları

### Downlink gönderilemiyor

1. Device Class A ise uplink sonrası mı?
2. Gateway downlink destekliyor mu?
3. Duty cycle limiti aşılmış mı?

```bash
docker compose logs stack 2>&1 | grep "Scheduling downlink" | tail -20
```

## Webhook Sorunları

### Webhook çağrılmıyor

1. Webhook URL doğru mu?
2. TLS sertifikası valid mi?
3. Timeout mu oluyor?

```bash
docker compose logs stack 2>&1 | grep "webhook" | tail -50
```

### Webhook 4xx/5xx

1. Endpoint erişilebilir mi?
```bash
curl -v <webhook-url>
```

2. Format doğru mu?
3. Authentication header'ları doğru mu?

## Performans Sorunları

### Yüksek latency

1. Resource kullanımı:
```bash
docker stats
```

2. PostgreSQL connection count:
```bash
docker compose exec postgres psql -U ttn -c "SELECT count(*) FROM pg_stat_activity;"
```

3. Redis memory:
```bash
docker compose exec redis redis-cli INFO memory
```

### High CPU/Memory

1. Container limits kontrol:
```bash
docker compose config | grep -A5 deploy
```

2. Log volume çok mu?
3. Event backlog var mı?

## Diagnostic Komutları Özeti

```bash
# Genel durum
./health-check.sh

# Container logları
docker compose logs -f stack

# PostgreSQL bağlantıları
docker compose exec postgres psql -U ttn -c "SELECT count(*) FROM pg_stat_activity;"

# Redis durumu
docker compose exec redis redis-cli INFO

# Network kontrol
ss -tlnp | grep -E "1700|1885|1884"

# Disk kullanımı
df -h
du -sh /var/lib/docker
```

## İlgili Skill

Detaylı troubleshooting için:
- `@troubleshooting` - Kapsamlı sorun giderme rehberi

## İlgili Komutlar

- `/logs` - Log görüntüleme
- `/status` - Sistem durumu
- `/test` - Bağlantı testleri
