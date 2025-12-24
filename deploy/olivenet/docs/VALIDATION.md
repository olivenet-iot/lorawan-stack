# Kurulum Dogrulama Checklist

Detayli rehber icin: [QUICKSTART.md](QUICKSTART.md)

## Hizli Checklist

```bash
cd /opt/lorawan-stack/deploy/olivenet

# 1. Health Check
./scripts/health-check.sh
# Beklenen: Status: HEALTHY

# 2. Full Validation
./scripts/validate.sh
# Beklenen: Failed: 0

# 3. Gateway Test
source simulator/activate.sh
python3 gateway_simulator.py --server YOUR_DOMAIN --port 1700 --eui AA555A0000000001 --test-only
# Beklenen: ✓ PULL_ACK received

# 4. Console
curl -sk https://YOUR_DOMAIN/healthz | jq .status
# Beklenen: "OK"
```

## Tum Kontroller Gecti mi?

| Kontrol | Komut | Beklenen |
|---------|-------|----------|
| Health | `./scripts/health-check.sh` | HEALTHY |
| Validate | `./scripts/validate.sh` | Failed: 0 |
| Gateway | `gateway_simulator.py --test-only` | PULL_ACK |
| Console | `curl .../healthz` | OK |
| MQTT | `mosquitto_sub -C 1` | Connection |

Tumu ✓ = Kurulum basarili!
