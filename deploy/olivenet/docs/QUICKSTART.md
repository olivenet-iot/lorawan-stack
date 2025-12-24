# TTS Kurulum ve Dogrulama Rehberi

Bu rehber, The Things Stack kurulumunu adim adim aciklar ve her adimin nasil dogrulanacagini gosterir.

---

## On Gereksinimler

### 1. Docker Kurulumu

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

**Dogrulama:**
```bash
docker --version
# Beklenen: Docker version 24.x veya uzeri
```

### 2. Git Kurulumu

```bash
sudo apt update && sudo apt install -y git
```

**Dogrulama:**
```bash
git --version
# Beklenen: git version 2.x
```

---

## Kurulum Adimlari

### Adim 1: Repo'yu Clone Et

```bash
sudo git clone -b v3.35 https://github.com/olivenet/lorawan-stack.git /opt/lorawan-stack
sudo chown -R $USER:docker /opt/lorawan-stack
cd /opt/lorawan-stack/deploy/olivenet
```

**Dogrulama:**
```bash
ls -la scripts/deploy.sh
# Beklenen: -rwxr-xr-x ... scripts/deploy.sh
```

### Adim 2: Deployment Baslat

```bash
./scripts/deploy.sh
```

**Sorular:**
- Domain: `tts.yourdomain.com`
- Email: `admin@yourdomain.com`
- TLS: `1` (Let's Encrypt)
- Testing tools: `Y`

**Beklenen Cikti:**
```
+================================================================+
|                   DEPLOYMENT COMPLETE                          |
+================================================================+

Console:  https://tts.yourdomain.com/console

Admin Credentials
------------------
  Username: admin
  Email:    admin@yourdomain.com
  Password: <generated>
```

### Adim 3: Health Check

```bash
./scripts/health-check.sh
```

**Beklenen Cikti:**
```
Olivenet TTS Health Check
==========================
  ✓ stack: Stack is healthy
  ✓ postgres: Connections: X
  ✓ redis: Memory: X.XXM
  ✓ disk: X% used
  ✓ memory: X% used
  ✓ docker: All 3 containers running
  ✓ ssl: Valid for X days
==========================
Status: HEALTHY
```

### Adim 4: Validasyon

```bash
./scripts/validate.sh
```

**Beklenen Cikti:**
```
================================================================
  Passed: 10+    Warnings: 0-2    Failed: 0
================================================================

All critical checks passed!
```

### Adim 5: Gateway Baglanti Testi

```bash
source simulator/activate.sh
python3 gateway_simulator.py --server YOUR_DOMAIN --port 1700 --eui AA555A0000000001 --test-only
```

**Beklenen Cikti:**
```
[12:00:00] Gateway AA555A0000000001 starting...
[12:00:00] Connecting to YOUR_DOMAIN:1700
[12:00:01] Gateway connected successfully
[12:00:01] ✓ PULL_ACK received
[12:00:01] Test mode: connection verified, exiting
```

### Adim 6: Console Erisimi

1. Browser'da ac: `https://YOUR_DOMAIN/console`
2. Deployment'tan aldigin credentials ile giris yap
3. Dashboard gorunmeli

**Dogrulama:**
```bash
curl -sk https://YOUR_DOMAIN/healthz | jq .status
# Beklenen: "OK"
```

### Adim 7: MQTT Testi (Opsiyonel)

1. Console'da bir Application olustur
2. Application -> Integrations -> MQTT -> Generate API Key
3. Test et:

```bash
mosquitto_sub -h YOUR_DOMAIN -p 8883 \
  --capath /etc/ssl/certs/ \
  -t "v3/APP_ID/devices/+/up" \
  -u "APP_ID" \
  -P "NNSXS.xxxxx" \
  -d -C 1 -W 10
```

Beklenen: Baglanti basarili (veri yoksa timeout normal)

---

## Sorun Giderme

### Container Baslamiyor

```bash
docker logs olivenet-stack --tail 50
```

### Console'a Giris Yapilamiyor

```bash
# OAuth grants kontrolu
docker exec olivenet-postgres psql -U ttn -d ttn_lorawan -c \
  "SELECT client_id, grants FROM clients WHERE client_id = 'console';"
# Beklenen: {0,2}

# Duzeltme:
docker exec olivenet-postgres psql -U ttn -d ttn_lorawan -c \
  "UPDATE clients SET grants = '{0,2}', skip_authorization = true WHERE client_id = 'console';"
docker compose restart stack
```

### Gateway Baglanmiyor

```bash
# Port kontrolu
docker exec olivenet-stack netstat -ulnp | grep 1700
# Beklenen: :::1700

# Firewall kontrolu
sudo ufw status
sudo ufw allow 1700/udp
```

### TLS Sertifikasi Yok

```bash
# ACME dizini kontrolu
ls -la acme/
# Beklenen: 886:886 ownership

# Duzeltme:
sudo chown -R 886:886 acme/
docker compose restart stack
```

---

## Hizli Referans

| Komut | Aciklama |
|-------|----------|
| `./scripts/deploy.sh` | Kurulum baslat |
| `./scripts/health-check.sh` | Servis durumu |
| `./scripts/validate.sh` | Tam dogrulama |
| `./scripts/setup-tools.sh` | Test araclari kur |
| `./scripts/backup.sh` | Yedek al |
| `./scripts/restore.sh` | Yedegi geri yukle |
| `docker compose logs -f stack` | Canli loglar |
| `docker compose restart stack` | Stack yeniden baslat |

---

## Port Referansi

| Port | Protokol | Kullanim |
|------|----------|----------|
| 80 | HTTP | Console/API (redirect) |
| 443 | HTTPS | Console/API |
| 1700/UDP | Semtech UDP | Gateway Packet Forwarder |
| 1882 | MQTT | GS Gateway |
| 8882 | MQTTS | GS Gateway (TLS) |
| 1883 | MQTT | AS Application |
| 8883 | MQTTS | AS Application (TLS) |
| 8887 | WSS | BasicStation Gateway |
