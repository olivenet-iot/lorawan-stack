# Olivenet TTS - Operations Guide

Bu dokuman, Olivenet TTS deployment'inin gunluk operasyonlari icin rehber niteligindedir.

## Hizli Basvuru

| Islem | Komut |
|-------|-------|
| Stack durumu | `docker-compose ps` |
| Logları izle | `docker-compose logs -f stack` |
| Health check | `./scripts/health-check.sh` |
| Manuel backup | `./scripts/backup.sh` |
| Restore | `./scripts/restore.sh <backup.tar.gz>` |

---

## Dizin Yapisi

```
/opt/olivenet-tts/
└── deploy/olivenet/
    ├── docker-compose.yml      # Production stack
    ├── docker-compose.dev.yml  # Development stack
    ├── .env                    # Environment variables
    ├── config/
    │   ├── ttn-lw-stack.yml    # TTS configuration
    │   └── alert.conf          # Alert configuration
    ├── scripts/
    │   ├── backup.sh           # Full backup
    │   ├── restore.sh          # Restore from backup
    │   ├── backup-cron.sh      # Cron wrapper
    │   ├── health-check.sh     # Health checks
    │   ├── monitor-daemon.sh   # Monitoring daemon
    │   ├── alert.sh            # Alert utility
    │   ├── status-page.sh      # Status page generator
    │   └── lib/
    │       └── common.sh       # Shared functions
    └── systemd/
        ├── olivenet-tts-monitor.service
        ├── olivenet-tts-backup.service
        └── olivenet-tts-backup.timer
```

---

## Backup Islemleri

### Manuel Backup

```bash
# Full backup
./scripts/backup.sh

# Sadece database
./scripts/backup.sh --db-only

# Sadece config
./scripts/backup.sh --config-only

# Ozel retention suresi
./scripts/backup.sh --retention 14
```

### Zamanlanmis Backup

Backup'lar gunluk olarak saat 02:00'de calisir. Timer durumu:

```bash
# Timer durumu
sudo systemctl status olivenet-tts-backup.timer

# Sonraki calisma zamani
sudo systemctl list-timers olivenet-tts-backup.timer

# Manuel tetikleme
sudo systemctl start olivenet-tts-backup.service
```

### Backup Lokasyonu

```
/var/backups/olivenet-tts/
├── daily/
│   ├── backup-20250120-020000.tar.gz
│   └── backup-20250121-020000.tar.gz
├── weekly/
│   └── backup-20250119-020000.tar.gz
├── logs/
│   └── backup.log
└── .latest -> daily/backup-20250121-020000.tar.gz
```

### Backup Icerigi

```bash
# Backup icerigini listele
./scripts/restore.sh --list backup-20250120-020000.tar.gz
```

---

## Restore Islemleri

### Tam Restore

```bash
# En son backup'tan restore
./scripts/restore.sh

# Belirli backup'tan restore
./scripts/restore.sh backup-20250120-020000.tar.gz

# Dry-run (degisiklik yapmadan)
./scripts/restore.sh --dry-run backup-20250120-020000.tar.gz
```

### Kısmi Restore

```bash
# Sadece database
./scripts/restore.sh --db-only backup-20250120-020000.tar.gz

# Sadece config
./scripts/restore.sh --config-only backup-20250120-020000.tar.gz
```

### Onemli Notlar

- Restore islemi oncesinde otomatik olarak mevcut durum backup'lanir
- `--skip-pre-backup` ile bu atlanabilir (onerılmez)
- Restore sonrasi stack otomatik restart edilir

---

## Health Check

### Manuel Kontrol

```bash
# Tum kontroller
./scripts/health-check.sh

# JSON output
./scripts/health-check.sh --json

# Belirli component
./scripts/health-check.sh --component stack
./scripts/health-check.sh --component postgres
./scripts/health-check.sh --component redis
```

### Kontrol Edilen Bilesenler

| Bilesen | Kontrol | Threshold |
|---------|---------|-----------|
| stack | /healthz endpoint | HTTP 200 |
| postgres | pg_isready | Connection count < 180 |
| redis | PING | Memory usage |
| disk | df | 80% usage |
| memory | free | 85% usage |
| docker | container status | All running |
| ssl | certificate expiry | 30 days |

### Exit Codes

| Code | Anlam |
|------|-------|
| 0 | Healthy |
| 1 | Degraded (warnings) |
| 2 | Critical (errors) |

---

## Monitoring

### Daemon Baslatma

```bash
# Daemon baslat
./scripts/monitor-daemon.sh start

# Durumu kontrol et
./scripts/monitor-daemon.sh status

# Durdur
./scripts/monitor-daemon.sh stop

# Yeniden baslat
./scripts/monitor-daemon.sh restart
```

### Systemd ile Yonetim

```bash
# Service durumu
sudo systemctl status olivenet-tts-monitor

# Loglari izle
sudo journalctl -u olivenet-tts-monitor -f

# Yeniden baslat
sudo systemctl restart olivenet-tts-monitor
```

### Monitoring Ozellikleri

- Her 60 saniyede health check
- 3 ardisik basarisizlikta alert
- Duzeldikten sonra recovery alert
- Status dosyasi: `/var/run/olivenet-tts-monitor.status`

---

## Alert Sistemi

### Alert Kanallari

1. **Telegram** - Aninda bildirim
2. **Email** - Detayli rapor
3. **Webhook** - Entegrasyonlar (Slack, Discord, PagerDuty)

### Yapilandirma

```bash
# Config dosyasini olustur
cp config/alert.conf.example config/alert.conf
chmod 600 config/alert.conf

# Gerekli degerleri duzenle
vim config/alert.conf
```

### Manuel Alert Gonderme

```bash
# Telegram
./scripts/alert.sh --telegram "Test message"

# Email
./scripts/alert.sh --email admin@olivenet.com "Test message"

# Webhook
./scripts/alert.sh --webhook "https://hooks.slack.com/..." "Test message"

# Tum kanallar
./scripts/alert.sh --all "Test message to all channels"
```

---

## Status Page

### Olusturma

```bash
# Varsayilan konum (/var/www/status)
./scripts/status-page.sh

# Ozel konum
./scripts/status-page.sh --output /var/www/html/status
```

### Nginx Yapilandirmasi

```nginx
server {
    listen 80;
    server_name status.olivenet.com;

    location / {
        root /var/www/status;
        index index.html;
    }
}
```

### Otomatik Guncelleme

Status page her 60 saniyede otomatik refresh yapar. Sureli guncelleme icin cron:

```cron
* * * * * /opt/olivenet-tts/deploy/olivenet/scripts/status-page.sh
```

---

## Log Yonetimi

### Log Lokasyonlari

| Log | Lokasyon |
|-----|----------|
| Stack logs | `docker-compose logs stack` |
| Backup logs | `/var/log/olivenet-tts/backup.log` |
| Monitor logs | `journalctl -u olivenet-tts-monitor` |
| Cron logs | `/var/log/olivenet-tts/backup-cron.log` |

### Log Filtreleme

```bash
# Son 100 satir
docker-compose logs --tail=100 stack

# Belirli zaman araligi
docker-compose logs --since="2025-01-20" stack

# Hata filtreleme
docker-compose logs stack 2>&1 | grep -i error
```

### Log Rotation

Docker log rotation docker-compose.yml'de yapilandirilmistir:
- Max size: 100MB
- Max files: 5

---

## Gunluk Operasyonlar

### Sabah Kontrolleri

1. Health check calistir: `./scripts/health-check.sh`
2. Son backup'i kontrol et: `ls -la /var/backups/olivenet-tts/.latest`
3. Disk kullanimini kontrol et: `df -h`
4. Log'larda hata ara: `docker-compose logs --since="24h" stack | grep -i error`

### Haftalik Gorevler

1. Backup integrity testi: `./scripts/restore.sh --dry-run $(readlink /var/backups/olivenet-tts/.latest)`
2. SSL sertifika kontrolu: `./scripts/health-check.sh --component ssl`
3. Disk temizligi: Eski log'lari sil

### Deployment

```bash
# Pull latest
git pull origin main

# Pull images
docker-compose pull

# Update stack
docker-compose up -d

# Migration (gerekirse)
docker-compose exec stack ttn-lw-stack is-db migrate
```

---

## Troubleshooting

Detayli sorun giderme icin: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

### Hizli Cozumler

**Stack baslamiyor:**
```bash
docker-compose logs stack | tail -50
docker-compose down && docker-compose up -d
```

**Database baglanti hatasi:**
```bash
docker-compose exec postgres pg_isready -U ttn
docker-compose restart postgres
```

**Redis baglanti hatasi:**
```bash
docker-compose exec redis redis-cli PING
docker-compose restart redis
```

**Memory yetersiz:**
```bash
docker stats
docker system prune -a
```

---

## CI/CD

GitHub Actions workflow'lari:

| Workflow | Trigger | Islem |
|----------|---------|-------|
| ci.yml | Push/PR | Lint, test, build |
| deploy.yml | Manual/Tag | Deploy to server |
| release.yml | Release | Build & publish |
| scheduled.yml | Cron | Security scan, backup verify |

### Manuel Deployment

```bash
# GitHub Actions üzerinden
# Actions > Deploy > Run workflow

# Veya sunucuda direkt
cd /opt/olivenet-tts
git pull
cd deploy/olivenet
docker-compose pull && docker-compose up -d
```

### Rollback

```bash
# Onceki commit'e don
git checkout HEAD~1
docker-compose up -d

# Veya belirli tag'e
git checkout v1.0.0
docker-compose up -d
```

---

## Ilgili Dokumanlar

- [ARCHITECTURE.md](ARCHITECTURE.md) - Sistem mimarisi
- [DEPLOYMENT.md](DEPLOYMENT.md) - Kurulum rehberi
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Sorun giderme
- [GITHUB-SECRETS.md](GITHUB-SECRETS.md) - CI/CD yapilandirma
- [CONFIG-VALIDATION-REPORT.md](CONFIG-VALIDATION-REPORT.md) - Config dogrulama
