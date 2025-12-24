# /device Command

End device management.

## Parameters

| Parameter | Description |
|-----------|-------------|
| list | List devices |
| create | Create new device |
| get | Device details |
| delete | Delete device |
| reset | Frame counter reset |
| keys | Show root keys |

## Procedure

### List Devices

```bash
ttn-lw-cli end-devices list <app-id>
```

JSON format:
```bash
ttn-lw-cli end-devices list <app-id> --output-format json
```

### Create Device (OTAA)

```bash
ttn-lw-cli end-devices create <app-id> <device-id> \
  --dev-eui <dev-eui> \
  --app-eui <app-eui> \
  --app-key <app-key> \
  --lorawan-version MAC_V1_0_3 \
  --lorawan-phy-version PHY_V1_0_3_REV_A \
  --frequency-plan-id EU_863_870
```

With key generation:
```bash
# Generate random key
APP_KEY=$(openssl rand -hex 16 | tr '[:lower:]' '[:upper:]')
echo "Generated AppKey: $APP_KEY"

ttn-lw-cli end-devices create <app-id> <device-id> \
  --dev-eui <dev-eui> \
  --app-eui 0000000000000000 \
  --app-key $APP_KEY \
  --lorawan-version MAC_V1_0_3 \
  --lorawan-phy-version PHY_V1_0_3_REV_A \
  --frequency-plan-id EU_863_870
```

### Create Device (ABP)

```bash
ttn-lw-cli end-devices create <app-id> <device-id> \
  --dev-addr <dev-addr> \
  --nwk-s-key <nwk-s-key> \
  --app-s-key <app-s-key> \
  --lorawan-version MAC_V1_0_3 \
  --lorawan-phy-version PHY_V1_0_3_REV_A \
  --frequency-plan-id EU_863_870 \
  --supports-join false
```

### Device Details

```bash
ttn-lw-cli end-devices get <app-id> <device-id>
```

Session info:
```bash
ttn-lw-cli end-devices get <app-id> <device-id> \
  --session \
  --output-format json
```

### Show Root Keys

```bash
ttn-lw-cli end-devices get <app-id> <device-id> --root-keys
```

### Frame Counter Reset

```bash
ttn-lw-cli end-devices set <app-id> <device-id> \
  --session.last-f-cnt-up 0 \
  --session.last-n-f-cnt-down 0
```

### Delete Device

```bash
ttn-lw-cli end-devices delete <app-id> <device-id>
```

### Update MAC Settings

```bash
ttn-lw-cli end-devices set <app-id> <device-id> \
  --mac-settings.adr.mode.dynamic \
  --mac-settings.rx1-delay RX_DELAY_1
```

### Device Events

```bash
ttn-lw-cli events subscribe \
  --application-id <app-id> \
  --device-id <device-id>
```

## Bulk Import

Import from CSV:

```bash
# CSV format:
# dev_eui,app_eui,app_key,name
# 70B3D57ED0000001,0000000000000000,00112233...,Device 1

ttn-lw-cli end-devices create-from-csv <app-id> devices.csv
```

## Example Outputs

### Device List

```
ID                  Name            DevEUI              Last Seen
device-001          Energy Meter 1  70B3D57ED0000001    5 minutes ago
device-002          Energy Meter 2  70B3D57ED0000002    1 hour ago
```

### Device Details

```yaml
ids:
  device_id: device-001
  application_ids:
    application_id: my-app
  dev_eui: 70B3D57ED0000001
  join_eui: 0000000000000000
lorawan_version: MAC_V1_0_3
lorawan_phy_version: PHY_V1_0_3_REV_A
frequency_plan_id: EU_863_870
session:
  dev_addr: 260B1234
  last_f_cnt_up: 1234
```

## Related Skill

- `@device-management` - Detailed device management

## Related Commands

- `/gateway` - Gateway management
- `/simulate` - Device simulation
