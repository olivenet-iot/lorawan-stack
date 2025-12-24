# Gateway Simulator

UDP Packet Forwarder protokolü ile TTS gateway bağlantısını test eder.

## Kullanım

```bash
# Ortamı aktifle
source activate.sh

# Hızlı bağlantı testi
python3 gateway_simulator.py \
  --server tts.olivenet.io \
  --port 1700 \
  --eui AA555A0000000001 \
  --test-only

# Sürekli çalıştır
python3 gateway_simulator.py \
  --server tts.olivenet.io \
  --port 1700 \
  --eui AA555A0000000001

# Debug modu
python3 gateway_simulator.py \
  --server tts.olivenet.io \
  --port 1700 \
  --eui AA555A0000000001 \
  --debug
```

## Parametreler

| Parametre | Varsayılan | Açıklama |
|-----------|------------|----------|
| --server | localhost | TTS sunucu adresi |
| --port | 1700 | UDP port |
| --eui | AA555A0000000001 | Gateway EUI |
| --test-only | false | Sadece bağlantı testi |
| --debug | false | Debug çıktısı |
| --interactive | false | İnteraktif mod |

## Beklenen Çıktı

```
[12:00:00] Gateway AA555A0000000001 starting...
[12:00:00] Connecting to tts.olivenet.io:1700
[12:00:01] Gateway connected successfully
[12:00:01] ✓ PULL_ACK received
```

PULL_ACK alınması = Gateway Server bağlantısı başarılı.
