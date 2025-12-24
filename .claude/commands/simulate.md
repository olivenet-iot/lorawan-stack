# /simulate Command

Runs LoRaWAN gateway simulator for testing TTS connectivity.

## Parameters

| Parameter | Description |
|-----------|-------------|
| gateway | Gateway simulator (default) |
| --server HOST | TTS server address |
| --port PORT | UDP port (default: 1700) |
| --eui EUI | Gateway EUI |
| --test-only | Connection test only |
| --interactive | Interactive mode |
| --debug | Debug output |

## Setup

Before using the simulator for the first time:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet

# Run setup script (recommended)
./scripts/setup-tools.sh

# Or manual setup
cd simulator
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Procedure

### /simulate gateway

Gateway connection simulation:

```bash
cd /home/ubuntu/lorawan-stack/deploy/olivenet/simulator
source activate.sh

# Connection test
python3 gateway_simulator.py --test-only

# With custom server
python3 gateway_simulator.py --server tts.olivenet.io --port 1700 --test-only

# Interactive mode
python3 gateway_simulator.py --interactive

# With custom EUI
python3 gateway_simulator.py --eui AA555A0000000099

# Debug mode
python3 gateway_simulator.py --debug
```

### Expected Output

```
[12:00:00] Gateway AA555A0000000001 starting...
[12:00:00] Connecting to localhost:1700
[12:00:01] Gateway connected successfully
[12:00:01] PULL_ACK received
[12:00:01] Test mode: connection verified, exiting
```

PULL_ACK received = Gateway Server connection successful.

## Important Notes

**CAUTION:**

1. **Stack must be running**
   - Gateway simulator connects to TTS Gateway Server
   - Port 1700/UDP must be open

2. **Virtual environment required**
   - Run `./scripts/setup-tools.sh` first
   - Or manually create venv and install requirements

3. **Config file (optional)**
   - Edit `config.yml` for default settings
   - Or create `config.local.yml` for local overrides

## Config Example

```yaml
# config.yml
stack:
  host: "localhost"
  gateway_udp_port: 1700

gateway:
  eui: "AA555A0000000001"
  frequency_plan: "EU_863_870"
```

## Simulator Features

| Feature | Description |
|---------|-------------|
| PULL_DATA | Keepalive packets (30s interval) |
| PUSH_DATA | Uplink frame injection |
| PULL_RESP | Downlink reception |
| Interactive | Manual uplink injection |
| Debug | Detailed packet logging |

## Related Documentation

- `deploy/olivenet/simulator/README.md` - Detailed simulator guide
- `docs/olivenet/SIMULATOR.md` - Full simulator documentation

## Related Commands

- `/test` - Basic tests
- `/device` - Device management
- `/gateway` - Gateway management
- `/status` - Stack status
