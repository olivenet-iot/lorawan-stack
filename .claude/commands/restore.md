# /restore Komutu

Backup'tan sistem geri yüklemesi yapar.

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| --latest | En son backup'ı kullan |
| --file PATH | Belirli backup dosyası |
| --dry-run | Ne yapılacağını göster, yapma |
| --db-only | Sadece database restore |
| --config-only | Sadece config restore |
| --force | Onay istemeden restore |

## Prosedür

### Son Backup'tan Restore

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/scripts
./restore.sh --latest --dry-run  # Önce kontrol et
./restore.sh --latest            # Gerçek restore
```

### Belirli Backup'tan Restore

```bash
# Mevcut backup'ları listele
ls -la /var/backups/olivenet-tts/daily/

# Belirli backup'ı restore et
./restore.sh --file /var/backups/olivenet-tts/daily/backup-20250120-100000.tar.gz
```

## Restore Süreci

1. **Pre-restore Safety Backup**
   - Mevcut durum yedeklenir
   - Rollback mümkün

2. **Stack Durdurma**
```bash
docker compose down
```

3. **Database Restore**
   - PostgreSQL dump yükleme
   - Foreign key kontrolleri

4. **Redis Restore**
   - RDB file yükleme

5. **Config Restore**
   - .env, YAML dosyaları

6. **Stack Başlatma**
```bash
docker compose up -d
```

7. **Verification**
```bash
./health-check.sh
```

## Dry-Run Çıktısı

```
[DRY-RUN] Restore from: backup-20250120-100000.tar.gz

Actions to perform:
1. Create safety backup of current state
2. Stop TTS stack
3. Restore PostgreSQL database (156MB)
4. Restore Redis data (12MB)
5. Restore configuration files
6. Start TTS stack
7. Run health check

Estimated time: 2-5 minutes

Run without --dry-run to execute.
```

## Uyarılar

⚠️ **DİKKAT:**
- Restore işlemi mevcut veriyi siler
- Production'da dikkatli olun
- Önce `--dry-run` ile test edin

## Hata Durumları

| Hata | Çözüm |
|------|-------|
| Backup file not found | Path'i kontrol et |
| Permission denied | Root olarak çalıştır |
| Database restore failed | Backup bütünlüğünü kontrol et |
| Stack won't start | Logları kontrol et, rollback yap |

## Rollback

Restore başarısız olursa:

```bash
./restore.sh --file /var/backups/olivenet-tts/pre-restore-safety.tar.gz
```

## İlgili Komutlar

- `/backup` - Backup oluştur
- `/status` - Restore sonrası durum kontrolü
