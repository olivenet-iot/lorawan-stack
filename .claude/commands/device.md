# /device Komutu

End device yönetimi.

## Parametreler

| Parametre | Açıklama |
|-----------|----------|
| list | Device'ları listele |
| create | Yeni device oluştur |
| get | Device detayları |
| delete | Device sil |
| reset | Frame counter reset |
| keys | Root key'leri göster |

## Prosedür

### Device Listele

```bash
ttn-lw-cli end-devices list <app-id>
```

JSON formatı:
```bash
ttn-lw-cli end-devices list <app-id> --output-format json
```

### Device Oluştur (OTAA)

```bash
ttn-lw-cli end-devices create <app-id> <device-id> \
  --dev-eui <dev-eui> \
  --app-eui <app-eui> \
  --app-key <app-key> \
  --lorawan-version MAC_V1_0_3 \
  --lorawan-phy-version PHY_V1_0_3_REV_A \
  --frequency-plan-id EU_863_870
```

Key generation ile:
```bash
# Random key generate et
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

### Device Oluştur (ABP)

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

### Device Detayları

```bash
ttn-lw-cli end-devices get <app-id> <device-id>
```

Session bilgisi:
```bash
ttn-lw-cli end-devices get <app-id> <device-id> \
  --session \
  --output-format json
```

### Root Keys Göster

```bash
ttn-lw-cli end-devices get <app-id> <device-id> --root-keys
```

### Frame Counter Reset

```bash
ttn-lw-cli end-devices set <app-id> <device-id> \
  --session.last-f-cnt-up 0 \
  --session.last-n-f-cnt-down 0
```

### Device Sil

```bash
ttn-lw-cli end-devices delete <app-id> <device-id>
```

### MAC Settings Güncelle

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

CSV'den import:

```bash
# CSV formatı:
# dev_eui,app_eui,app_key,name
# 70B3D57ED0000001,0000000000000000,00112233...,Device 1

ttn-lw-cli end-devices create-from-csv <app-id> devices.csv
```

## Örnek Çıktılar

### Device List

```
ID                  Name            DevEUI              Last Seen
device-001          Enerji Sayaç 1  70B3D57ED0000001    5 minutes ago
device-002          Enerji Sayaç 2  70B3D57ED0000002    1 hour ago
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

## İlgili Skill

- `@device-management` - Detaylı device yönetimi

## İlgili Komutlar

- `/gateway` - Gateway yönetimi
- `/simulate` - Device simülasyonu
