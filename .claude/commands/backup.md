# /backup Komutu

Sistem backup'ı oluşturur.

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| --db-only | Sadece database backup |
| --config-only | Sadece config backup |
| --full | Tam backup (varsayılan) |
| --retention DAYS | Saklama süresi (gün) |
| --output DIR | Çıktı dizini |

## Prosedür

### Tam Backup

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/scripts
./backup.sh
```

### Database Only

```bash
./backup.sh --db-only
```

### Config Only

```bash
./backup.sh --config-only
```

### Özel Retention

```bash
./backup.sh --retention 30  # 30 gün sakla
```

## Backup İçeriği

Tam backup şunları içerir:

1. **PostgreSQL Database**
   - Tüm tablolar (pg_dump)
   - Users, organizations, applications, devices
   - API keys, sessions

2. **Redis Data**
   - RDB snapshot
   - Device state, session cache

3. **Configuration Files**
   - .env
   - docker-compose.yml
   - ttn-lw-stack.yml

4. **Blob Storage** (opsiyonel)
   - Profile pictures
   - Uploaded files

## Backup Lokasyonu

```
/var/backups/olivenet-tts/
├── daily/
│   ├── backup-20250122-100000.tar.gz
│   └── backup-20250121-100000.tar.gz
├── weekly/
│   └── backup-20250120-020000.tar.gz
└── logs/
    └── backup.log
```

## Otomatik Backup

Cron ile otomatik backup:

```bash
# Systemd timer kullanılıyor
systemctl status olivenet-tts-backup.timer
```

## Başarı Çıktısı

```
[2025-01-22 10:00:00] [INFO] Starting backup...
[2025-01-22 10:00:01] [INFO] Backing up PostgreSQL...
[2025-01-22 10:00:15] [INFO] Backing up Redis...
[2025-01-22 10:00:16] [INFO] Backing up configuration...
[2025-01-22 10:00:17] [INFO] Creating archive...
[2025-01-22 10:00:20] [SUCCESS] Backup completed: backup-20250122-100000.tar.gz (45MB)
[2025-01-22 10:00:20] [INFO] Cleaning old backups...
[2025-01-22 10:00:21] [INFO] Retention: 7 days, removed 2 old backups
```

## İlgili Komutlar

- `/restore` - Backup'tan geri yükle
- `/status` - Son backup bilgisi

## İlgili Skill

- `@database-operations` - Detaylı backup prosedürleri
