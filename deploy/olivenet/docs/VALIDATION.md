# Installation Validation Checklist

For detailed guide see: [QUICKSTART.md](QUICKSTART.md)

## Quick Checklist

```bash
cd /opt/lorawan-stack/deploy/olivenet

# 1. Health Check
./scripts/health-check.sh
# Expected: Status: HEALTHY

# 2. Full Validation
./scripts/validate.sh
# Expected: Failed: 0

# 3. Gateway Test
source simulator/activate.sh
python3 gateway_simulator.py --server YOUR_DOMAIN --port 1700 --eui AA555A0000000001 --test-only
# Expected: ✓ PULL_ACK received

# 4. Console
curl -sk https://YOUR_DOMAIN/healthz | jq .status
# Expected: "OK"
```

## Did All Checks Pass?

| Check | Command | Expected |
|-------|---------|----------|
| Health | `./scripts/health-check.sh` | HEALTHY |
| Validate | `./scripts/validate.sh` | Failed: 0 |
| Gateway | `gateway_simulator.py --test-only` | PULL_ACK |
| Console | `curl .../healthz` | OK |
| MQTT | `mosquitto_sub -C 1` | Connection |

All ✓ = Installation successful!
