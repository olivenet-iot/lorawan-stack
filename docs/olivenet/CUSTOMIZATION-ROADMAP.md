# The Things Stack - Customization Roadmap (Olivenet)

## Overview

This document outlines the customization strategy for adapting The Things Stack to Olivenet's 3000+ energy meter infrastructure, including integration with existing ThingsBoard platform.

## Customization Phases

### Phase 1: Core Integration
- Energy meter payload formatters
- Webhook integration with ThingsBoard
- Device provisioning workflow

### Phase 2: Operational Enhancements
- Bulk device management
- Gateway monitoring dashboard
- Alert integration

### Phase 3: Advanced Features
- Multi-tenant organization structure
- Custom reporting
- API extensions

---

## Phase 1: Core Integration

### 1.1 Energy Meter Payload Formatters

**Goal**: Decode raw LoRaWAN payloads from energy meters into structured JSON.

**Implementation Location**: `pkg/applicationserver/io/formatters/`

**Example Energy Meter Payload**:
```
Raw bytes: 01 17 00 64 00 50 00 00 12 34
           │  │  │  │  │  │  │  │  └───┘ meter_id (4660)
           │  │  │  │  │  │  └──┘ reserved
           │  │  └──┴──┘ power: 80W
           │  │  └──┴──┘ current: 0.100A
           │  └──┘ voltage: 230V (23.0 * 10)
           └───── message_type: 0x01 = reading
```

**JavaScript Formatter**:
```javascript
function decodeUplink(input) {
  var bytes = input.bytes;
  var data = {};
  var warnings = [];
  var errors = [];

  if (bytes.length < 10) {
    errors.push("Invalid payload length");
    return { data: data, warnings: warnings, errors: errors };
  }

  var msgType = bytes[0];

  if (msgType === 0x01) { // Meter reading
    data.message_type = "reading";
    data.voltage = ((bytes[1] << 8) | bytes[2]) / 10;       // V
    data.current = ((bytes[3] << 8) | bytes[4]) / 1000;     // A
    data.power = (bytes[5] << 8) | bytes[6];                // W
    data.meter_id = (bytes[8] << 8) | bytes[9];

    // Energy calculation (Wh accumulated)
    if (bytes.length >= 14) {
      data.energy = ((bytes[10] << 24) | (bytes[11] << 16) |
                     (bytes[12] << 8) | bytes[13]) / 1000;  // kWh
    }

    // Validation warnings
    if (data.voltage < 200 || data.voltage > 260) {
      warnings.push("Voltage out of normal range");
    }
    if (data.power < 0 || data.power > 10000) {
      warnings.push("Power reading unusual");
    }
  } else if (msgType === 0x02) { // Alert
    data.message_type = "alert";
    data.alert_code = bytes[1];
    data.alert_codes = {
      0x01: "over_voltage",
      0x02: "under_voltage",
      0x03: "over_current",
      0x04: "power_outage",
      0x05: "tamper_detected"
    };
    data.alert_name = data.alert_codes[data.alert_code] || "unknown";
  }

  return { data: data, warnings: warnings, errors: errors };
}

function encodeDownlink(input) {
  // For meter configuration commands
  var bytes = [];
  if (input.data.command === "set_reporting_interval") {
    bytes.push(0x10);  // Command type
    bytes.push((input.data.interval >> 8) & 0xFF);
    bytes.push(input.data.interval & 0xFF);
  }
  return { bytes: bytes, fPort: 2 };
}
```

**Registration via API**:
```bash
curl -X PUT "https://lorawan.olivenet.com/api/v3/as/applications/energy-meters/payload-formatters/uplink" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "formatter": "FORMATTER_JAVASCRIPT",
    "formatter_parameter": "<formatter_code_here>"
  }'
```

### 1.2 ThingsBoard Webhook Integration

**Goal**: Forward decoded uplinks to ThingsBoard for visualization and storage.

**Webhook Configuration**:
```json
{
  "ids": {
    "webhook_id": "thingsboard-telemetry",
    "application_ids": {
      "application_id": "energy-meters"
    }
  },
  "base_url": "https://thingsboard.olivenet.com",
  "format": "json",
  "uplink_message": {
    "path": "/api/v1/${dev_eui}/telemetry"
  },
  "headers": {
    "Content-Type": "application/json"
  },
  "downlink_ack": null,
  "downlink_nack": null,
  "downlink_sent": null,
  "downlink_failed": null,
  "downlink_queued": null,
  "location_solved": null,
  "service_data": null
}
```

**ThingsBoard Payload Template**:
```json
{
  "ts": ${received_at},
  "values": {
    "voltage": ${decoded_payload.voltage},
    "current": ${decoded_payload.current},
    "power": ${decoded_payload.power},
    "energy": ${decoded_payload.energy},
    "rssi": ${rx_metadata[0].rssi},
    "snr": ${rx_metadata[0].snr}
  }
}
```

**Create Webhook via CLI**:
```bash
ttn-lw-cli applications webhooks set energy-meters thingsboard-telemetry \
  --base-url "https://thingsboard.olivenet.com" \
  --format json \
  --uplink-message.path "/api/v1/\${dev_eui}/telemetry"
```

### 1.3 Device Provisioning Workflow

**Bulk Import Script**:
```python
#!/usr/bin/env python3
# bulk_provision.py

import csv
import requests

API_URL = "https://lorawan.olivenet.com/api/v3"
API_KEY = "NNSXS.xxx"
APP_ID = "energy-meters"

def provision_device(row):
    device = {
        "end_device": {
            "ids": {
                "device_id": f"meter-{row['meter_id']}",
                "dev_eui": row['dev_eui'],
                "join_eui": row['join_eui'],
                "application_ids": {"application_id": APP_ID}
            },
            "name": f"Energy Meter {row['meter_id']}",
            "description": f"Location: {row['location']}",
            "lorawan_version": "MAC_V1_0_3",
            "lorawan_phy_version": "PHY_V1_0_3_REV_A",
            "frequency_plan_id": "EU_863_870",
            "supports_join": True,
            "root_keys": {
                "app_key": {"key": row['app_key']}
            }
        },
        "field_mask": {
            "paths": [
                "ids", "name", "description",
                "lorawan_version", "lorawan_phy_version",
                "frequency_plan_id", "supports_join", "root_keys"
            ]
        }
    }

    response = requests.post(
        f"{API_URL}/applications/{APP_ID}/devices",
        headers={"Authorization": f"Bearer {API_KEY}"},
        json=device
    )
    return response.status_code == 200

# Usage: python bulk_provision.py devices.csv
if __name__ == "__main__":
    import sys
    with open(sys.argv[1]) as f:
        reader = csv.DictReader(f)
        for row in reader:
            if provision_device(row):
                print(f"Provisioned: {row['meter_id']}")
            else:
                print(f"Failed: {row['meter_id']}")
```

**CSV Format**:
```csv
meter_id,dev_eui,join_eui,app_key,location
001,0102030405060708,0102030405060708,01020304050607080102030405060708,Building A
002,0102030405060709,0102030405060708,01020304050607080102030405060709,Building A
```

---

## Phase 2: Operational Enhancements

### 2.1 Gateway Monitoring

**Custom Gateway Status Webhook**:
```json
{
  "ids": {
    "webhook_id": "gateway-monitor",
    "application_ids": {
      "application_id": "gw-management"
    }
  },
  "base_url": "https://monitoring.olivenet.com",
  "gateway_status": {
    "path": "/gateways/${gateway_id}/status"
  }
}
```

**Prometheus Metrics Dashboard** (Grafana):
```yaml
# Gateway panel queries
- expr: gs_connected_gateways_total
  legendFormat: "Connected Gateways"

- expr: rate(gs_uplink_received_total[5m])
  legendFormat: "Uplinks/sec"

- expr: histogram_quantile(0.95, gs_uplink_latency_seconds_bucket)
  legendFormat: "P95 Latency"
```

### 2.2 Alert Integration

**Alert Webhook to PagerDuty/Slack**:
```javascript
// Payload formatter that triggers alerts
function decodeUplink(input) {
  var data = decodeEnergyMeter(input.bytes);

  // Add alert flags
  if (data.alert_code) {
    data._alert = {
      severity: data.alert_code <= 2 ? "warning" : "critical",
      message: `Energy meter ${data.meter_id}: ${data.alert_name}`,
      timestamp: new Date().toISOString()
    };
  }

  return { data: data };
}
```

**Webhook Filter for Alerts**:
```bash
# Only forward messages with alerts
ttn-lw-cli applications webhooks set energy-meters alert-webhook \
  --base-url "https://hooks.slack.com/services/xxx" \
  --format json \
  --uplink-message.path "/incoming" \
  --field-mask "uplink_message"
```

### 2.3 Bulk Operations API

**Custom CLI Commands**:
```bash
# Export all devices
ttn-lw-cli end-devices list energy-meters --all \
  --output-format json > devices-backup.json

# Update all devices' ADR settings
for dev in $(ttn-lw-cli end-devices list energy-meters --all --output-format json | jq -r '.[].ids.device_id'); do
  ttn-lw-cli end-devices set energy-meters $dev \
    --mac-settings.adr.mode.static.data-rate-index 3
done
```

---

## Phase 3: Advanced Features

### 3.1 Multi-Tenant Organization Structure

```
Olivenet (Organization)
├── energy-meters (Application)
│   ├── Building A Meters
│   ├── Building B Meters
│   └── Industrial Zone Meters
├── gateways (Application for GW management)
└── shared-gateways (Collaborator access)

Customer Organizations:
├── Customer-A (Organization)
│   └── customer-a-meters (Application)
│       └── Collaborator: building-a-gw
├── Customer-B (Organization)
...
```

**Create Organization Structure**:
```bash
# Create customer organization
ttn-lw-cli organizations create customer-a \
  --name "Customer A" \
  --user-id admin

# Create application
ttn-lw-cli applications create customer-a-meters \
  --organization-id customer-a \
  --name "Customer A Meters"

# Share gateway
ttn-lw-cli gateways collaborators set building-a-gw \
  --organization-id customer-a \
  --right-gateway-link
```

### 3.2 Custom Reporting

**Data Export API Extension**:
```go
// pkg/applicationserver/io/reports/energy_report.go
type EnergyReportService struct {
    as *ApplicationServer
}

func (s *EnergyReportService) GenerateDailyReport(ctx context.Context, req *ReportRequest) (*Report, error) {
    // Query uplinks for date range
    // Aggregate by device
    // Calculate totals, averages
    // Return report
}
```

**Scheduled Report Job**:
```yaml
# Add to stack config
as:
  scheduled-jobs:
    - name: daily-energy-report
      schedule: "0 6 * * *"  # 6 AM daily
      job: generate-energy-report
      config:
        output: webhook
        webhook-url: "https://reports.olivenet.com/energy"
```

### 3.3 Custom Dashboard Integration

**MQTT PubSub for Real-time Data**:
```yaml
# Enable MQTT pubsub
as:
  pubsub:
    providers:
      mqtt:
        address: mqtt.olivenet.com:8883
        username: tts
        password: ${MQTT_PASSWORD}
```

**Subscribe to Device Data**:
```javascript
// Node.js MQTT subscriber
const mqtt = require('mqtt');

const client = mqtt.connect('mqtts://mqtt.olivenet.com:8883', {
  username: 'energy-meters@olivenet',
  password: API_KEY
});

client.subscribe('v3/energy-meters@olivenet/devices/+/up');

client.on('message', (topic, message) => {
  const data = JSON.parse(message);
  // Process real-time meter data
  console.log(`Device: ${data.end_device_ids.device_id}`);
  console.log(`Power: ${data.uplink_message.decoded_payload.power}W`);
});
```

---

## Implementation Timeline

| Phase | Task | Priority |
|-------|------|----------|
| 1.1 | Payload Formatters | High |
| 1.2 | ThingsBoard Webhook | High |
| 1.3 | Device Provisioning | High |
| 2.1 | Gateway Monitoring | Medium |
| 2.2 | Alert Integration | Medium |
| 2.3 | Bulk Operations | Medium |
| 3.1 | Multi-Tenant Structure | Low |
| 3.2 | Custom Reporting | Low |
| 3.3 | Dashboard Integration | Low |

---

## Code Locations for Customization

| Feature | Directory/File |
|---------|---------------|
| Payload Formatters | `pkg/applicationserver/io/formatters/` |
| Webhooks | `pkg/applicationserver/io/web/webhooks.go` |
| PubSub | `pkg/applicationserver/io/pubsub/` |
| Device Registry | `pkg/identityserver/store/end_device_store.go` |
| Gateway Status | `pkg/gatewayserver/gatewayserver.go` |
| CLI Extensions | `cmd/ttn-lw-cli/commands/` |
| Console UI | `pkg/webui/console/` |

---

## Testing Customizations

### Unit Testing Formatters
```go
func TestEnergyMeterDecoder(t *testing.T) {
    input := []byte{0x01, 0x00, 0xE6, 0x00, 0x64, 0x00, 0x50, 0x00, 0x12, 0x34}
    result, err := DecodeEnergyMeter(input)

    assert.NoError(t, err)
    assert.Equal(t, 230.0, result.Voltage)
    assert.Equal(t, 0.1, result.Current)
    assert.Equal(t, 80, result.Power)
}
```

### Integration Testing Webhooks
```bash
# Mock webhook server
python -m http.server 8080 &

# Configure test webhook
ttn-lw-cli applications webhooks set test-app test-webhook \
  --base-url "http://localhost:8080"

# Send test uplink
ttn-lw-cli simulate uplink test-app test-device --f-port 1 --payload "01E6006400500012340"
```
