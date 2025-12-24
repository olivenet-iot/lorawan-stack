# Gateway Simulator

Tests TTS gateway connection using UDP Packet Forwarder protocol.

## Usage

```bash
# Activate environment
source activate.sh

# Quick connection test
python3 gateway_simulator.py \
  --server tts.olivenet.io \
  --port 1700 \
  --eui AA555A0000000001 \
  --test-only

# Run continuously
python3 gateway_simulator.py \
  --server tts.olivenet.io \
  --port 1700 \
  --eui AA555A0000000001

# Debug mode
python3 gateway_simulator.py \
  --server tts.olivenet.io \
  --port 1700 \
  --eui AA555A0000000001 \
  --debug
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| --server | localhost | TTS server address |
| --port | 1700 | UDP port |
| --eui | AA555A0000000001 | Gateway EUI |
| --test-only | false | Connection test only |
| --debug | false | Debug output |
| --interactive | false | Interactive mode |

## Expected Output

```
[12:00:00] Gateway AA555A0000000001 starting...
[12:00:00] Connecting to tts.olivenet.io:1700
[12:00:01] Gateway connected successfully
[12:00:01] ✓ PULL_ACK received
```

PULL_ACK received = Gateway Server connection successful.
