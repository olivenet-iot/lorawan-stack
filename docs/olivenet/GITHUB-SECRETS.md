# GitHub Secrets Configuration

Bu dokuman, Olivenet TTS CI/CD pipeline'larinin calismasıi icin gerekli GitHub secret'larını aciklar.

## Gerekli Secrets

### Deployment Secrets (Zorunlu)

| Secret | Aciklama | Ornek |
|--------|----------|-------|
| `DEPLOY_SSH_KEY` | Sunucu SSH private key | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `DEPLOY_HOST` | Sunucu IP veya hostname | `192.168.1.100` veya `tts.olivenet.com` |
| `DEPLOY_USER` | SSH kullanici adi | `deploy` veya `ubuntu` |

### Notification Secrets (Opsiyonel)

| Secret | Aciklama | Ornek |
|--------|----------|-------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot API token | `123456789:ABCdefGHIjklMNOpqrsTUVwxyz` |
| `TELEGRAM_CHAT_ID` | Telegram chat/group ID | `-1001234567890` |

---

## Secret Olusturma

### 1. SSH Key Olusturma

Sunucuya erisim icin SSH key cift olusturun:

```bash
# Yeni SSH key olustur
ssh-keygen -t ed25519 -C "github-deploy@olivenet" -f ~/.ssh/github_deploy

# Public key'i sunucuya ekle
ssh-copy-id -i ~/.ssh/github_deploy.pub deploy@sunucu-ip

# Private key icerigi (DEPLOY_SSH_KEY icin)
cat ~/.ssh/github_deploy
```

**Onemli Notlar:**
- Passphrase kullanmayin (bos birakin)
- Private key'in tamamini kopyalayin (`-----BEGIN` ile `-----END` arasindaki her sey)
- Sunucuda `/home/deploy/.ssh/authorized_keys` dosyasina public key eklendiginden emin olun

### 2. Deploy User Olusturma

Sunucuda ozel bir deploy kullanicisi olusturun:

```bash
# Kullanici olustur
sudo useradd -m -s /bin/bash deploy

# Docker grubuna ekle
sudo usermod -aG docker deploy

# Deployment dizinine erisim ver
sudo chown -R deploy:deploy /opt/olivenet-tts

# SSH dizini olustur
sudo -u deploy mkdir -p /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
```

### 3. Telegram Bot Olusturma

1. Telegram'da [@BotFather](https://t.me/BotFather) ile konusun
2. `/newbot` komutu ile yeni bot olusturun
3. Bot adini ve kullanici adini girin
4. Verilen API token'i `TELEGRAM_BOT_TOKEN` olarak kaydedin

Chat ID almak icin:
```bash
# Botu bir gruba ekleyin, sonra:
curl "https://api.telegram.org/bot<TOKEN>/getUpdates"
# Cevaptaki chat.id degerini kullanin
```

---

## GitHub'da Secret Ekleme

### Repository Secrets

1. GitHub repository'nize gidin
2. **Settings** > **Secrets and variables** > **Actions**
3. **New repository secret** tiklayin
4. Secret adini ve degerini girin

### Environment Secrets

Production ve staging icin ayri secret'lar kullanmak isterseniz:

1. **Settings** > **Environments**
2. `staging` ve `production` environment'lari olusturun
3. Her environment icin ayri secret'lar ekleyin

---

## Secret Referanslari

### ci.yml
```yaml
# Herhangi bir secret gerektirmez
# Opsiyonel: CODECOV_TOKEN (coverage upload icin)
```

### deploy.yml
```yaml
secrets:
  - DEPLOY_SSH_KEY      # Zorunlu
  - DEPLOY_HOST         # Zorunlu
  - DEPLOY_USER         # Zorunlu
  - TELEGRAM_BOT_TOKEN  # Opsiyonel
  - TELEGRAM_CHAT_ID    # Opsiyonel
```

### release.yml
```yaml
secrets:
  - GITHUB_TOKEN        # Otomatik (repository'de var)
  - TELEGRAM_BOT_TOKEN  # Opsiyonel
  - TELEGRAM_CHAT_ID    # Opsiyonel
```

### scheduled.yml
```yaml
secrets:
  - DEPLOY_SSH_KEY      # Backup verification icin
  - DEPLOY_HOST         # Backup verification icin
  - DEPLOY_USER         # Backup verification icin
  - TELEGRAM_BOT_TOKEN  # Alert icin
  - TELEGRAM_CHAT_ID    # Alert icin
```

---

## Guvenlik Onerileri

1. **SSH Key Rotation**: SSH key'leri 6 ayda bir degistirin
2. **Minimal Permissions**: Deploy kullanicisina sadece gerekli izinleri verin
3. **IP Whitelist**: Mumkunse sunucuda GitHub Actions IP'lerini whitelist'e alin
4. **Audit Logs**: GitHub Actions log'larini duzenli kontrol edin
5. **Environment Protection**: Production environment'a protection rule ekleyin

### Environment Protection Rules

Production environment icin onerilir:
- Required reviewers (en az 1 onay)
- Wait timer (5 dakika bekleme)
- Deployment branches (sadece main/master)

```
Settings > Environments > production > Protection rules
```

---

## Sorun Giderme

### SSH Baglantı Hatası

```
Error: ssh: connect to host xxx port 22: Connection refused
```

**Cozum:**
1. Sunucuda SSH servisinin calistigini kontrol edin
2. Firewall'da 22 portunu acin
3. `DEPLOY_HOST` degerinin dogru oldugunu kontrol edin

### Permission Denied

```
Error: Permission denied (publickey)
```

**Cozum:**
1. SSH key'in dogru formatta oldugunu kontrol edin
2. Sunucuda authorized_keys dosyasini kontrol edin
3. Dosya izinlerini kontrol edin:
   ```bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```

### Telegram Notification Hatası

```
Error: Bad Request: chat not found
```

**Cozum:**
1. Bot'un gruba eklendiginden emin olun
2. Chat ID'nin dogru oldugunu kontrol edin (grup ID'leri negatif sayilarla baslar)
3. Bot'a mesaj gonderme izni verildigini kontrol edin
