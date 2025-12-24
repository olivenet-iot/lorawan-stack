# LoRaWAN Gateway Simulator - User Guide

This documentation describes the LoRaWAN gateway simulator tool developed for Olivenet TTS.

## Overview

The simulator is used to test The Things Stack gateway connectivity without physical hardware. It is Python-based and implements the Semtech UDP Packet Forwarder protocol.

**Features:**
- Gateway connection testing (PULL_DATA/PULL_ACK)
- Virtual uplink injection
- Downlink reception and logging
- Interactive mode for manual testing

## Directory Structure

```
deploy/olivenet/simulator/
├── README.md                    # Quick start
├── requirements.txt             # Python dependencies
├── config.yml                   # Configuration
├── activate.sh                  # Environment activation
├── lib/
│   ├── __init__.py
│   ├── lorawan_crypto.py        # LoRaWAN cryptography
│   ├── packet_forwarder.py      # Semtech UDP protocol
│   └── gateway.py               # Virtual gateway
└── gateway_simulator.py         # Gateway simulator
```

## Installation

### Automatic Setup (Recommended)

```bash
cd deploy/olivenet
./scripts/setup-tools.sh
```

### Manual Setup

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
```

### Local Configuration

Create `config.local.yml` for production values:

```bash
cp config.yml config.local.yml
nano config.local.yml
```

## Usage

### Quick Start

```bash
# Activate environment
source activate.sh

# Connection test
python3 gateway_simulator.py --test-only
```

### Command Line Options

```bash
# Connection test
python3 gateway_simulator.py --test-only

# Interactive mode
python3 gateway_simulator.py --interactive

# Custom settings
python3 gateway_simulator.py \
  --eui AA555A0000000099 \
  --server tts.olivenet.io \
  --port 1700

# Debug mode
python3 gateway_simulator.py --debug
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| --server | localhost | TTS server address |
| --port | 1700 | UDP port |
| --eui | AA555A0000000001 | Gateway EUI |
| --test-only | false | Connection test only |
| --debug | false | Debug output |
| --interactive | false | Interactive mode |

### Expected Output

```
[12:00:00] Gateway AA555A0000000001 starting...
[12:00:00] Connecting to localhost:1700
[12:00:01] Gateway connected successfully
[12:00:01] PULL_ACK received
[12:00:01] Test mode: connection verified, exiting
```

**PULL_ACK received** = Gateway Server connection successful.

## Interactive Mode

In interactive mode, you can manually inject uplink frames:

```
Commands:
  status     - Show gateway status
  uplink     - Send test uplink
  quit       - Exit simulator

gateway> status
Gateway: AA555A0000000001
Connected: Yes
Uplinks sent: 0
Last PULL_ACK: 2s ago

gateway> uplink
Sending test uplink...
Uplink sent successfully

gateway> quit
Disconnecting...
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

### pycryptodome import error

```bash
# Reinstall with force
cd deploy/olivenet
./scripts/setup-tools.sh --force
```

### Connection timeout

1. Check network connectivity:
```bash
ping <tts-host>
```

2. Check firewall:
```bash
sudo ufw status
sudo ufw allow 1700/udp
```

## API Usage

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

    # Send PULL_DATA and wait for PULL_ACK
    ack = await gateway.pull_data()
    print(f"PULL_ACK received: {ack}")

    await gateway.disconnect()

asyncio.run(main())
```

### LoRaWAN Crypto

```python
from lib.lorawan_crypto import (
    compute_mic,
    encrypt_payload,
)

# Compute MIC
mic = compute_mic(
    key=bytes(16),
    data=b'\x00\x01\x02\x03',
)

# Encrypt payload
encrypted = encrypt_payload(
    key=bytes(16),
    payload=b'Hello',
    dev_addr=0x260B1234,
    fcnt=1,
    direction=0,  # uplink
)
```

## Protocol Reference

### Semtech UDP Packet Forwarder

| Packet | Direction | Description |
|--------|-----------|-------------|
| PUSH_DATA | GW → Server | Uplink frames |
| PUSH_ACK | Server → GW | Uplink acknowledgment |
| PULL_DATA | GW → Server | Keepalive (30s) |
| PULL_ACK | Server → GW | Keepalive response |
| PULL_RESP | Server → GW | Downlink frames |
| TX_ACK | GW → Server | Transmission result |

### Packet Structure

```
PUSH_DATA: [version(1)][random(2)][identifier(1)][gateway_eui(8)][json_payload]
PULL_DATA: [version(1)][random(2)][identifier(1)][gateway_eui(8)]
```

## Related Documentation

- [OPERATIONS.md](OPERATIONS.md) - Operational procedures
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Troubleshooting guide
- [DEPLOYMENT.md](DEPLOYMENT.md) - Deployment guide
