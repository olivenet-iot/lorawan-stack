# Claude Code Custom Commands - Olivenet TTS

Bu dizin, TTS yönetimi için özel Claude Code komutlarını içerir.

## Kullanım

Komutlar "/" prefix'i ile çağrılır:

```
/deploy          - TTS'i deploy et
/status          - Sistem durumunu göster
/test            - Testleri çalıştır
/backup          - Backup al
/restore         - Backup'tan restore et
/logs            - Logları göster
/troubleshoot    - Sorun giderme
/device          - Device yönetimi
/gateway         - Gateway yönetimi
/simulate        - Simulator çalıştır
```

## Komut Detayları

Her komut alt parametreler alabilir:

```bash
/deploy --check      # Sadece preflight check
/deploy --dry-run    # Ne yapacağını göster, yapma
/status --json       # JSON formatında
/test gateway        # Sadece gateway testi
/logs ns --tail 100  # Network Server son 100 log
```

## Komut Listesi

| Komut | Dosya | Açıklama |
|-------|-------|----------|
| /deploy | deploy.md | Stack deployment ve güncelleme |
| /status | status.md | Sistem durumu ve health check |
| /test | test.md | Testleri çalıştır |
| /backup | backup.md | Backup oluştur |
| /restore | restore.md | Backup'tan geri yükle |
| /logs | logs.md | Log görüntüleme |
| /troubleshoot | troubleshoot.md | Sorun giderme |
| /device | device.md | Device yönetimi |
| /gateway | gateway.md | Gateway yönetimi |
| /simulate | simulate.md | Simulator çalıştır |

## İlgili Skill'ler

Bu komutlar aşağıdaki skill'lerle entegredir:

- `@troubleshooting` - Sorun giderme rehberi
- `@device-management` - Device yönetim prosedürleri
- `@gateway-management` - Gateway yönetim prosedürleri
- `@database-operations` - Backup/restore işlemleri

## Dosya Dizini

```
.claude/commands/
├── README.md           # Bu dosya
├── deploy.md           # /deploy komutu
├── status.md           # /status komutu
├── test.md             # /test komutu
├── backup.md           # /backup komutu
├── restore.md          # /restore komutu
├── logs.md             # /logs komutu
├── troubleshoot.md     # /troubleshoot komutu
├── device.md           # /device komutu
├── gateway.md          # /gateway komutu
└── simulate.md         # /simulate komutu
```
