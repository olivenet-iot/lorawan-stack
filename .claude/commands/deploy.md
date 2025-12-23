# /deploy Komutu

TTS stack'i deploy eder veya günceller.

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| --check | Sadece preflight check yap |
| --dry-run | Ne yapılacağını göster, yapma |
| --force | Mevcut .env'i overwrite et |
| --skip-oauth | OAuth setup'ı atla (tekrar çalıştırma) |
| --no-backup | Güncelleme öncesi backup alma |

## Prosedür

### Otomatik Deployment (Önerilen)

deploy.sh scripti tüm adımları otomatik yapar:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet
./scripts/deploy.sh
```

**Script şunları yapar:**
1. Kullanıcıdan domain ve email ister
2. TLS seçimi (Let's Encrypt / Self-signed / None)
3. Tüm secret'ları otomatik generate eder
4. .env dosyası oluşturur
5. ACME dizinini oluşturur (doğru izinlerle)
6. Database'leri başlatır
7. Migration yapar
8. Admin user ve OAuth client'ları oluşturur
9. OAuth grants'ları düzeltir (kritik!)
10. Stack'i başlatır
11. Admin credentials'ları gösterir

### Dry Run

Değişiklik yapmadan ne olacağını görmek için:

```bash
./scripts/deploy.sh --dry-run
```

### Tekrar Deployment

Mevcut deployment'ı yeniden başlatmak için:

```bash
./scripts/deploy.sh --skip-oauth --force
```

### Manuel Deployment

Eğer manuel yapmak isterseniz:

1. **Preflight Check**
```bash
./scripts/preflight-check.sh
```

2. **Environment Hazırlığı**
```bash
cp .env.example .env
nano .env  # Değerleri doldurun

# Secret'lar için:
openssl rand -hex 32  # CONSOLE_OAUTH_CLIENT_SECRET
openssl rand -hex 16  # BLOCK_KEY
openssl rand -hex 32  # HASH_KEY
```

3. **ACME Dizini**
```bash
mkdir -p acme
sudo chown 886:886 acme
```

4. **Database Başlat**
```bash
docker compose up -d postgres redis
sleep 15
```

5. **Migration**
```bash
docker compose run --rm stack is-db migrate
```

6. **Admin User**
```bash
docker compose run --rm stack is-db create-admin-user \
  --id admin \
  --email admin@yourdomain.com \
  --password <password>
```

7. **OAuth Clients**
```bash
# CLI client
docker compose run --rm stack is-db create-oauth-client \
  --id cli --name "CLI" --owner admin --no-secret \
  --redirect-uri "local-callback" --redirect-uri "code"

# Console client
docker compose run --rm stack is-db create-oauth-client \
  --id console --name "Console" --owner admin \
  --secret "${CONSOLE_OAUTH_CLIENT_SECRET}" \
  --redirect-uri "https://yourdomain.com/console/oauth/callback" \
  --logout-redirect-uri "https://yourdomain.com/console"
```

8. **OAuth Grants Fix (KRİTİK!)**
```bash
docker compose exec -T postgres psql -U ttn -d ttn_lorawan -c \
  "UPDATE clients SET grants = '{0,2}', skip_authorization = true, endorsed = true WHERE client_id = 'console';"
```

9. **Stack Başlat**
```bash
docker compose up -d stack
```

## Güncelleme

```bash
# Backup al
./scripts/backup.sh

# Image güncelle
docker compose pull
docker compose up -d

# Migration (gerekirse)
docker compose run --rm stack is-db migrate
```

## Başarı Durumu

```
╔════════════════════════════════════════════════════════════════╗
║                   DEPLOYMENT COMPLETE                         ║
╚════════════════════════════════════════════════════════════════╝

Console:  https://tts.olivenet.io/console

Admin Credentials
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Username: admin
  Email:    admin@olivenet.io
  Password: ************

IMPORTANT: Change the admin password immediately after first login!
```

## Hata Durumları

| Hata | Çözüm |
|------|-------|
| Port in use | `ss -tlnp \| grep <port>` ile process'i bul |
| Docker not running | `systemctl start docker` |
| ACME failed | DNS kayıtları doğru mu? Port 80 açık mı? |
| OAuth error | grants fix SQL komutunu çalıştır |
| Migration failed | Logları göster: `docker compose logs stack` |

## Kritik Notlar

⚠️ **OAuth Grants**: Console login için grants fix SQL komutu kritik!
```sql
UPDATE clients SET grants = '{0,2}', skip_authorization = true, endorsed = true WHERE client_id = 'console';
```

⚠️ **ACME Permissions**: ACME dizini 886:886 olmalı (TTS container user)

⚠️ **Config Template**: Değişiklik yapmak için:
- `config/ttn-lw-stack.yml.template` - Template dosyası
- `config/ttn-lw-stack.yml` - Aktif config

## İlgili Komutlar

- `/status` - Deployment durumunu kontrol et
- `/backup` - Backup al
- `/troubleshoot` - Sorun giderme
