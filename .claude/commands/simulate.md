# /simulate Command

Runs LoRaWAN simulator.

## Parameters

| Parameter | Description |
|-----------|-------------|
| gateway | Gateway simulator |
| device | Device simulator |
| traffic | Traffic generator |
| join | Join tester |
| --scenario FILE | Scenario file |
| --devices N | Number of devices |
| --duration S | Duration (seconds) |

## Setup

Before using the simulator for the first time:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/simulator

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

## Procedure

### /simulate gateway

Gateway connection simulation:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/simulator
source venv/bin/activate

# Connection test
python gateway_simulator.py --test-only

# Interactive mode
python gateway_simulator.py --interactive

# With custom EUI
python gateway_simulator.py --eui AA555A0000000099
```

### /simulate device

Device simulation:

```bash
# Single device OTAA join
python device_simulator.py \
  --dev-eui 70B3D57ED0000001 \
  --app-key 00112233445566778899AABBCCDDEEFF \
  --uplinks 5

# With scenario file
python device_simulator.py --scenario scenarios/single_device.yml
```

### /simulate join

Detailed join analysis:

```bash
python join_tester.py \
  --dev-eui 70B3D57ED0000001 \
  --app-key 00112233445566778899AABBCCDDEEFF
```

Output:
```
OTAA Join Test - DevEUI: 70B3D57ED0000001
============================================================

Step 1: Preparing Join Request
├── DevEUI: 70B3D57ED0000001
├── JoinEUI: 0000000000000000
├── DevNonce: 0x1A2B
└── MIC: 0xAABBCCDD

Step 2: Sending via Gateway
├── Frequency: 868.1 MHz
└── Data Rate: SF7BW125

Step 3: Waiting for Join Accept...
✓ Received!
└── Response time: 4.82s

Step 4: Processing Join Accept
├── DevAddr: 260B1234
└── ✓ MIC Valid

Step 5: Deriving Session Keys
├── NwkSKey: 11223344...
└── AppSKey: FFEEDDCC...

✓ JOIN SUCCESSFUL
```

### /simulate traffic

Load testing:

```bash
# 100 devices, 10 uplinks/sec, 5 minutes
python traffic_generator.py \
  --devices 100 \
  --rate 10 \
  --duration 300

# With scenario file
python traffic_generator.py --scenario scenarios/stress_test.yml

# 5000 device stress test
python traffic_generator.py --scenario scenarios/stress_test.yml
```

Output:
```
Traffic Generator - 100 devices, 10 uplinks/sec
============================================================

Joining: 100%|██████████| 100/100 [00:45<00:00]
  joined: 98, failed: 2

Traffic: 100%|██████████| 300/300 [05:00<00:00]
  uplinks: 3000, rate: 10.0/s

Test Summary
============================================================
Duration:             300.5s
Devices joined:       98/100 (98.0%)
Uplinks sent:         2940
Uplinks/sec:          9.8
Errors:               2
```

## Available Scenarios

| Scenario | Description | Usage |
|----------|-------------|-------|
| `single_device.yml` | Single device join + uplink | Basic test |
| `multi_device.yml` | 10 devices parallel | Multiple devices |
| `join_storm.yml` | 100 devices simultaneous | Join stress |
| `sustained_traffic.yml` | 50 devices, 5 min | Sustainability |
| `stress_test.yml` | 5000 devices, 10 min | Production load |

## Important Notes

⚠️ **CAUTION:**

1. **Simulator connects to stack**
   - Stack must be running
   - Port 1700/UDP must be open

2. **Test devices must be registered in TTS**
   - Simulator doesn't auto-register
   - Create via Console or CLI

3. **AppKey must match**
   - Simulator AppKey = TTS AppKey

4. **Config file**
   - Edit `config.yml`
   - Or create `config.local.yml`

## Config Example

```yaml
# config.yml
stack:
  host: "localhost"
  gateway_udp_port: 1700

gateway:
  eui: "AA555A0000000001"

device:
  dev_eui_prefix: "70B3D57ED0"
  join_eui: "0000000000000000"
```

## Result Files

Results are stored in `results/` directory:

```
results/
├── stress_test_20250122_123456.json
├── simulator.log
└── .gitkeep
```

## Related Documentation

- `deploy/olivenet/simulator/README.md` - Detailed simulator guide

## Related Commands

- `/test` - Basic tests
- `/device` - Device management (for registration)
- `/gateway` - Gateway management
