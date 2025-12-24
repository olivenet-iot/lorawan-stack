# /gateway Command

Gateway management.

## Parameters

| Parameter | Description |
|-----------|-------------|
| list | List gateways |
| create | Create new gateway |
| get | Gateway details |
| delete | Delete gateway |
| stats | Connection statistics |
| status | Connection status |

## Procedure

### List Gateways

```bash
ttn-lw-cli gateways list
```

JSON format:
```bash
ttn-lw-cli gateways list --output-format json
```

### Create Gateway

```bash
ttn-lw-cli gateways create <gateway-id> \
  --gateway-eui <gateway-eui> \
  --frequency-plan-id EU_863_870 \
  --name "Olivenet Gateway 1"
```

With location:
```bash
ttn-lw-cli gateways create <gateway-id> \
  --gateway-eui <gateway-eui> \
  --frequency-plan-id EU_863_870 \
  --name "Olivenet Gateway 1" \
  --antenna.location.latitude 35.1856 \
  --antenna.location.longitude 33.3823 \
  --antenna.location.altitude 50
```

### Gateway Details

```bash
ttn-lw-cli gateways get <gateway-id>
```

### Connection Status

Via API:
```bash
curl -H "Authorization: Bearer $API_KEY" \
  "http://localhost:1885/api/v3/gs/gateways/<gateway-id>/connection/stats"
```

Via CLI:
```bash
ttn-lw-cli gateways get <gateway-id> --gateway-server-address
```

### Statistics

```bash
# From Gateway Server logs
docker compose logs stack 2>&1 | grep "gateway_eui=<EUI>" | tail -50
```

### Update Gateway

Update location:
```bash
ttn-lw-cli gateways set <gateway-id> \
  --antenna.location.latitude 35.1856 \
  --antenna.location.longitude 33.3823
```

### Delete Gateway

```bash
ttn-lw-cli gateways delete <gateway-id>
```

### Gateway Events

```bash
ttn-lw-cli events subscribe --gateway-id <gateway-id>
```

## Frequency Plans

Show available frequency plans:
```bash
ttn-lw-cli frequency-plans list
```

For EU868:
- `EU_863_870` - EU 863-870 MHz
- `EU_863_870_TTN` - TTN default

## Gateway Protocols

| Protocol | Port | Description |
|----------|------|-------------|
| UDP Packet Forwarder | 1700/UDP | Legacy protocol |
| BasicStation | 8887/WSS | Modern protocol |
| MQTT | 1883/TCP | MQTT gateway |

### UDP Packet Forwarder Connection

```bash
# Connection test
nc -uvz localhost 1700
```

### BasicStation Connection

Gateway config:
```json
{
  "uri": "wss://lora.olivenet.com:8887"
}
```

## Example Outputs

### Gateway List

```
ID              Name                EUI                 Status
gw-001          Olivenet GW 1       AA555A0000000001    Connected
gw-002          Olivenet GW 2       AA555A0000000002    Disconnected
```

### Gateway Stats

```json
{
  "connected_at": "2025-01-22T10:00:00Z",
  "last_uplink_at": "2025-01-22T12:34:56Z",
  "uplink_count": 12345,
  "downlink_count": 234,
  "round_trip_times": {
    "min": "45ms",
    "max": "120ms",
    "median": "67ms"
  }
}
```

## Troubleshooting

### Gateway not connecting

1. Is EUI correct?
2. Is port 1700 open?
3. Is frequency plan compatible?

```bash
# Check logs
docker compose logs stack 2>&1 | grep "gs:" | grep -i error
```

### Uplink not received

1. Is antenna connected?
2. Is device frequency correct?
3. Is RSSI/SNR sufficient?

## Related Skill

- `@gateway-management` - Detailed gateway management

## Related Commands

- `/device` - Device management
- `/simulate` - Gateway simulation
- `/test gateway` - Gateway connection test
