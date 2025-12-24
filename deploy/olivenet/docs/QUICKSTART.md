# TTS Installation and Validation Guide

This guide explains The Things Stack installation step by step and shows how to validate each step.

---

## Prerequisites

### 1. Docker Installation

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

**Validation:**
```bash
docker --version
# Expected: Docker version 24.x or higher
```

### 2. Git Installation

```bash
sudo apt update && sudo apt install -y git
```

**Validation:**
```bash
git --version
# Expected: git version 2.x
```

---

## Installation Steps

### Step 1: Clone the Repository

```bash
sudo git clone -b v3.35 https://github.com/olivenet/lorawan-stack.git /opt/lorawan-stack
sudo chown -R $USER:docker /opt/lorawan-stack
cd /opt/lorawan-stack/deploy/olivenet
```

**Validation:**
```bash
ls -la scripts/deploy.sh
# Expected: -rwxr-xr-x ... scripts/deploy.sh
```

### Step 2: Start Deployment

```bash
./scripts/deploy.sh
```

**Questions:**
- Domain: `tts.yourdomain.com`
- Email: `admin@yourdomain.com`
- TLS: `1` (Let's Encrypt)
- Testing tools: `Y`

**Expected Output:**
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

### Step 3: Health Check

```bash
./scripts/health-check.sh
```

**Expected Output:**
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

### Step 4: Validation

```bash
./scripts/validate.sh
```

**Expected Output:**
```
================================================================
  Passed: 10+    Warnings: 0-2    Failed: 0
================================================================

All critical checks passed!
```

### Step 5: Gateway Connection Test

```bash
source simulator/activate.sh
python3 gateway_simulator.py --server YOUR_DOMAIN --port 1700 --eui AA555A0000000001 --test-only
```

**Expected Output:**
```
[12:00:00] Gateway AA555A0000000001 starting...
[12:00:00] Connecting to YOUR_DOMAIN:1700
[12:00:01] Gateway connected successfully
[12:00:01] ✓ PULL_ACK received
[12:00:01] Test mode: connection verified, exiting
```

### Step 6: Console Access

1. Open in browser: `https://YOUR_DOMAIN/console`
2. Login with credentials from deployment
3. Dashboard should be visible

**Validation:**
```bash
curl -sk https://YOUR_DOMAIN/healthz | jq .status
# Expected: "OK"
```

### Step 7: MQTT Test (Optional)

1. Create an Application in Console
2. Application -> Integrations -> MQTT -> Generate API Key
3. Test:

```bash
mosquitto_sub -h YOUR_DOMAIN -p 8883 \
  --capath /etc/ssl/certs/ \
  -t "v3/APP_ID/devices/+/up" \
  -u "APP_ID" \
  -P "NNSXS.xxxxx" \
  -d -C 1 -W 10
```

Expected: Connection successful (timeout is normal if no data)

---

## Troubleshooting

### Container Not Starting

```bash
docker logs olivenet-stack --tail 50
```

### Cannot Login to Console

```bash
# OAuth grants check
docker exec olivenet-postgres psql -U ttn -d ttn_lorawan -c \
  "SELECT client_id, grants FROM clients WHERE client_id = 'console';"
# Expected: {0,2}

# Fix:
docker exec olivenet-postgres psql -U ttn -d ttn_lorawan -c \
  "UPDATE clients SET grants = '{0,2}', skip_authorization = true WHERE client_id = 'console';"
docker compose restart stack
```

### Gateway Not Connecting

```bash
# Port check
docker exec olivenet-stack netstat -ulnp | grep 1700
# Expected: :::1700

# Firewall check
sudo ufw status
sudo ufw allow 1700/udp
```

### No TLS Certificate

```bash
# ACME directory check
ls -la acme/
# Expected: 886:886 ownership

# Fix:
sudo chown -R 886:886 acme/
docker compose restart stack
```

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `./scripts/deploy.sh` | Start installation |
| `./scripts/health-check.sh` | Service status |
| `./scripts/validate.sh` | Full validation |
| `./scripts/setup-tools.sh` | Install test tools |
| `./scripts/backup.sh` | Create backup |
| `./scripts/restore.sh` | Restore from backup |
| `docker compose logs -f stack` | Live logs |
| `docker compose restart stack` | Restart stack |

---

## Port Reference

| Port | Protocol | Usage |
|------|----------|-------|
| 80 | HTTP | Console/API (redirect) |
| 443 | HTTPS | Console/API |
| 1700/UDP | Semtech UDP | Gateway Packet Forwarder |
| 1882 | MQTT | GS Gateway |
| 8882 | MQTTS | GS Gateway (TLS) |
| 1883 | MQTT | AS Application |
| 8883 | MQTTS | AS Application (TLS) |
| 8887 | WSS | BasicStation Gateway |
