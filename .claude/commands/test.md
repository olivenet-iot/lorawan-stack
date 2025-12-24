# /test Command

Runs system tests.

## Parameters

| Parameter | Description |
|-----------|-------------|
| gateway | Gateway connection test |
| device | Device join test |
| api | API endpoint test |
| all | All tests |
| --scenario FILE | Test with scenario file |

## Procedure

### /test gateway

Gateway connection test:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/simulator
source venv/bin/activate
python gateway_simulator.py --test-only
```

Expected output:
- PULL_DATA sent
- PULL_ACK received
- Connection successful

### /test device

Device join test:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/simulator
python join_tester.py \
  --dev-eui 70B3D57ED0000001 \
  --app-key 00112233445566778899AABBCCDDEEFF
```

**Note:** Device must be registered in TTS!

### /test api

API endpoint test:

```bash
# Health endpoint
curl -s http://localhost:1885/healthz

# Authenticated endpoint (API key required)
curl -s -H "Authorization: Bearer $API_KEY" \
  http://localhost:1885/api/v3/applications
```

### /test all

Run all tests sequentially:
1. API tests
2. Gateway tests
3. Device tests

## Test Results

```
Test Results - 2025-01-22 12:34:56

API Tests:
  ✓ Health endpoint (23ms)
  ✓ Auth endpoint (45ms)
  ✓ Device list (89ms)
  ✓ Gateway list (67ms)

Gateway Tests:
  ✓ UDP connection (1.2s)
  ✓ PULL_ACK received (0.8s)

Device Tests:
  ✓ OTAA join (4.5s)
  ✓ Uplink delivered (0.9s)
  ✓ Device visible in Console

Summary: 9/9 tests passed
```

## Scenario Test

```bash
python device_simulator.py --scenario scenarios/single_device.yml
```

## Error States

| Error | Possible Cause |
|-------|----------------|
| Gateway connection failed | Port 1700 closed, TTS not running |
| Join timeout | Device not registered, wrong AppKey |
| API 401 | Invalid or missing API key |

## Related Commands

- `/simulate` - More comprehensive simulation
- `/troubleshoot` - Error analysis
