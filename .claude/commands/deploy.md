# /deploy Komutu

TTS stack'i deploy eder veya günceller.

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| --check | Sadece preflight check yap |
| --dry-run | Ne yapılacağını göster, yapma |
| --force | Preflight uyarılarını atla |
| --no-backup | Güncelleme öncesi backup alma |
| --pull | Sadece image'ları güncelle |

## Prosedür

### İlk Deployment

1. **Preflight Check**
```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet
./scripts/preflight-check.sh
```
   - Kritik hata varsa DUR ve kullanıcıya bildir
   - Uyarı varsa kullanıcıya sor

2. **Environment Hazırlığı**
   - .env dosyası yoksa:
```bash
cp .env.example .env
```
   - Kullanıcıdan eksik değerleri iste
   - Secret'ları generate et:
```bash
# Cookie keys
openssl rand -hex 32  # HASH_KEY
openssl rand -hex 16  # BLOCK_KEY
# OAuth secret
openssl rand -hex 32
```

3. **Docker Network Oluştur**
```bash
docker network create olivenet-tts || true
```

4. **Stack'i Başlat**
```bash
docker compose pull
docker compose up -d
```

5. **Database Migration**
```bash
docker compose exec stack /ttn-lw-stack is-db migrate
```

6. **Admin User Oluştur** (ilk kurulum)
```bash
docker compose exec stack /ttn-lw-stack is-db create-admin-user \
  --id admin \
  --email admin@olivenet.com \
  --password <generated>
```

7. **Health Check**
```bash
./scripts/health-check.sh
```

### Güncelleme

1. Mevcut durumu kontrol et:
```bash
./scripts/health-check.sh
```

2. Backup al (--no-backup yoksa):
```bash
./scripts/backup.sh
```

3. Image'ları güncelle:
```bash
docker compose pull
docker compose up -d
```

4. Migration varsa çalıştır:
```bash
docker compose exec stack /ttn-lw-stack is-db migrate
```

5. Health check:
```bash
./scripts/health-check.sh
```

## Başarı Durumu

```
✓ TTS deployed successfully!

Console: https://lora.olivenet.com
Admin User: admin
Admin Password: ********

Next steps:
1. Login to Console
2. Create an Application
3. Add your first Gateway
```

## Hata Durumları

| Hata | Çözüm |
|------|-------|
| Port in use | `ss -tlnp \| grep <port>` ile process'i bul |
| Docker not running | `systemctl start docker` |
| Migration failed | Logları göster, rollback öner |
| Health check failed | `/troubleshoot` komutunu öner |

## İlgili Komutlar

- `/status` - Deployment durumunu kontrol et
- `/backup` - Backup al
- `/troubleshoot` - Sorun giderme
