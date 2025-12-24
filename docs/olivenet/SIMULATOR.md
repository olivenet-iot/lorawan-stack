# LoRaWAN Simulator - User Guide

This documentation describes the LoRaWAN simulator tools developed for Olivenet TTS.

## Overview

The simulator is used to test The Things Stack without physical gateways and devices. It is Python-based and supports the following features:

- **Gateway Simulator**: Semtech UDP Packet Forwarder protocol
- **Device Simulator**: OTAA/ABP device simulation
- **Traffic Generator**: 5000+ device load testing
- **Join Tester**: OTAA join flow analysis

## Directory Structure

```
deploy/olivenet/simulator/
├── README.md                    # Quick start
├── requirements.txt             # Python dependencies
├── config.yml                   # Configuration
├── lib/
│   ├── __init__.py
│   ├── lorawan_crypto.py        # LoRaWAN cryptography
│   ├── packet_forwarder.py      # Semtech UDP protocol
│   ├── device.py                # Virtual device
│   └── gateway.py               # Virtual gateway
├── gateway_simulator.py         # Gateway simulator
├── device_simulator.py          # Device simulator
├── traffic_generator.py         # Load testing
├── join_tester.py               # Join analysis
├── scenarios/                   # Test scenarios
│   ├── single_device.yml
│   ├── multi_device.yml
│   ├── join_storm.yml
│   ├── sustained_traffic.yml
│   └── stress_test.yml
└── results/                     # Test results
```

## Installation

```bash
cd deploy/olivenet/simulator

# Virtual environment
python3 -m venv venv
source venv/bin/activate

# Dependencies
pip install -r requirements.txt
```

## Configuration

### config.yml

```yaml
stack:
  host: "localhost"              # TTS server
  gateway_udp_port: 1700         # Gateway UDP port

gateway:
  eui: "AA555A0000000001"        # Gateway EUI
  frequency_plan: "EU_863_870"   # Frequency plan
  location:
    latitude: 35.1856            # North Cyprus
    longitude: 33.3823
    altitude: 50

device:
  dev_eui_prefix: "70B3D57ED0"   # DevEUI prefix
  join_eui: "0000000000000000"   # JoinEUI
  lorawan_version: "1.0.3"       # LoRaWAN version

simulation:
  uplink_interval: 60            # Uplink interval (seconds)
  data_rate: 5                   # SF7BW125
```

### Local Configuration

Create `config.local.yml` for production values:

```bash
cp config.yml config.local.yml
nano config.local.yml
```

## Tools

### Gateway Simulator

Virtual gateway connection:

```bash
# Connection test
python gateway_simulator.py --test-only

# Interactive mode
python gateway_simulator.py --interactive

# Custom settings
python gateway_simulator.py \
  --eui AA555A0000000099 \
  --server lora.olivenet.com \
  --port 1700
```

**Features:**
- Semtech UDP Packet Forwarder protocol
- PULL_DATA keepalive (30s interval)
- Downlink reception and logging
- Interactive uplink injection

### Device Simulator

Virtual device OTAA/ABP:

```bash
# OTAA join + uplink
python device_simulator.py \
  --dev-eui 70B3D57ED0000001 \
  --app-key 00112233445566778899AABBCCDDEEFF \
  --uplinks 5

# With scenario
python device_simulator.py --scenario scenarios/single_device.yml

# ABP
python device_simulator.py \
  --abp \
  --dev-addr 260B1234 \
  --nwk-s-key 00112233445566778899AABBCCDDEEFF \
  --app-s-key FFEEDDCCBBAA00998877665544332211
```

### Join Tester

Detailed OTAA join analysis:

```bash
python join_tester.py \
  --dev-eui 70B3D57ED0000001 \
  --app-key 00112233445566778899AABBCCDDEEFF
```

**Output:**
- Join Request details (DevNonce, MIC)
- Join Accept processing
- Session key derivation
- Timing analysis

### Traffic Generator

Load testing:

```bash
# Basic test
python traffic_generator.py \
  --devices 100 \
  --rate 10 \
  --duration 300

# Stress test
python traffic_generator.py --scenario scenarios/stress_test.yml
```

**Features:**
- Asyncio-based parallel processing
- Memory-efficient (5000+ devices)
- Progress bar
- Detailed statistics

## Scenarios

### single_device.yml
- Purpose: Basic functionality test
- 1 device, OTAA join, 5 uplinks
- Usage: Quick smoke test

### multi_device.yml
- Purpose: Multiple device test
- 10 devices in parallel
- Usage: Concurrent device handling

### join_storm.yml
- Purpose: Join Server stress test
- 100 devices joining simultaneously
- Usage: Join capacity test

### sustained_traffic.yml
- Purpose: Sustainability test
- 50 devices, 5 minutes continuous traffic
- Usage: Stability test

### stress_test.yml
- Purpose: Production load simulation
- 5000 devices, 10 minutes
- 500 uplinks/second
- Usage: Capacity planning

## API Usage

### VirtualDevice

```python
from lib.device import VirtualDevice

device = VirtualDevice(
    dev_eui=bytes.fromhex('70B3D57ED0000001'),
    join_eui=bytes(8),
    app_key=bytes.fromhex('00112233445566778899AABBCCDDEEFF'),
)

# OTAA Join
join_request = device.build_join_request()
# ... send via gateway ...
device.process_join_accept(join_accept_payload)

# Uplink
uplink = device.build_uplink(port=1, payload=b'\x01\x02\x03')
# ... send via gateway ...
```

### VirtualGateway

```python
from lib.gateway import VirtualGateway, GatewayConfig

config = GatewayConfig(
    eui="AA555A0000000001",
    server_host="localhost",
    server_port=1700,
)

gateway = VirtualGateway(config=config)

async def main():
    await gateway.connect()
    await gateway.send_uplink(phy_payload, radio_params)
    await gateway.disconnect()

asyncio.run(main())
```

### LoRaWAN Crypto

```python
from lib.lorawan_crypto import (
    compute_join_request_mic,
    derive_session_keys,
    encrypt_frm_payload,
)

# Compute MIC
mic = compute_join_request_mic(
    app_key=bytes(16),
    mhdr=0x00,
    join_eui=bytes(8),
    dev_eui=bytes(8),
    dev_nonce=0x1234,
)

# Derive session keys
nwk_s_key, app_s_key = derive_session_keys(
    app_key=bytes(16),
    join_nonce=bytes(3),
    net_id=bytes(3),
    dev_nonce=0x1234,
)
```

## Troubleshooting

### Gateway not connecting

1. Is TTS running?
```bash
docker compose ps
```

2. Is port 1700 open?
```bash
ss -ulnp | grep 1700
nc -uvz localhost 1700
```

3. Is config correct?
```bash
cat config.yml | grep -A5 stack
```

### Join failed

1. Is device registered in TTS?
```bash
ttn-lw-cli end-devices get <app-id> <device-id>
```

2. Does AppKey match?
```bash
ttn-lw-cli end-devices get <app-id> <device-id> --root-keys
```

3. Run join tester:
```bash
python join_tester.py --dev-eui <eui> --app-key <key>
```

### Low performance

1. Check network latency:
```bash
ping <tts-host>
```

2. Check TTS resource usage:
```bash
docker stats
```

3. Reduce rate limit:
```bash
python traffic_generator.py --rate 5  # Lower rate
```

## Test Results

Results are stored in the `results/` directory in JSON format:

```json
{
  "timestamp": "2025-01-22T12:34:56Z",
  "devices_total": 100,
  "devices_joined": 98,
  "join_success_rate": 98.0,
  "uplinks_sent": 4850,
  "uplinks_per_second": 16.2,
  "duration": 300.5,
  "errors": 2
}
```

## Best Practices

1. **Start small**: Test with `single_device.yml` first
2. **Scale gradually**: 10 → 100 → 1000 → 5000 devices
3. **Monitor TTS resources**: Use `docker stats`
4. **Save results**: Use `--output results/test_name.json`
5. **Check logs**: Monitor TTS logs

## Related Documentation

- [OPERATIONS.md](OPERATIONS.md) - Operational procedures
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Troubleshooting guide
- [DEPLOYMENT.md](DEPLOYMENT.md) - Deployment guide
