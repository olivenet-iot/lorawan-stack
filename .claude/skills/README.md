# The Things Stack - Claude Code Skills

Bu dizin, The Things Stack (TTS) projesi için Claude Code'un domain knowledge'ını içeren skill dosyalarını barındırır.

## Skills Listesi

| Skill | Açıklama | Kullanım Alanı |
|-------|----------|----------------|
| [api-usage](./api-usage/SKILL.md) | gRPC/REST API kullanımı | API entegrasyonu, client development |
| [device-management](./device-management/SKILL.md) | End device lifecycle yönetimi | Device provisioning, OTAA/ABP |
| [gateway-management](./gateway-management/SKILL.md) | Gateway yapılandırma | Gateway kurulum, protokoller |
| [lorawan-protocol](./lorawan-protocol/SKILL.md) | LoRaWAN protokol implementasyonu | MAC commands, class operations |
| [stack-internals](./stack-internals/SKILL.md) | Stack iç mimarisi | Component interaction, request flow |
| [database-operations](./database-operations/SKILL.md) | Database yönetimi | PostgreSQL, Redis, migrations |
| [performance-optimization](./performance-optimization/SKILL.md) | Performans tuning | Optimization, scaling |
| [troubleshooting](./troubleshooting/SKILL.md) | Sorun giderme | Debug, log analysis |

## Proje Yapısı

```
lorawan-stack/
├── api/ttn/lorawan/v3/          # Proto tanımları (58 dosya)
├── pkg/
│   ├── networkserver/           # Network Server implementasyonu
│   │   ├── grpc_gsns.go         # GS-NS gRPC handler
│   │   └── mac/                 # MAC command handlers (50+ dosya)
│   ├── applicationserver/       # Application Server implementasyonu
│   │   ├── grpc.go              # NS-AS gRPC handler
│   │   └── io/                  # Output integrations (mqtt, web, pubsub)
│   ├── gatewayserver/           # Gateway Server implementasyonu
│   │   └── io/                  # Gateway protocols (udp, semtechws, mqtt)
│   ├── identityserver/          # Identity Server (auth, registry)
│   │   └── store/migrations/    # Database migrations
│   └── joinserver/              # Join Server (OTAA key management)
├── data/lorawan-frequency-plans/ # Frequency plan definitions
└── deploy/olivenet/             # Deployment configuration
```

## Ana Bileşenler

### Network Server (NS)
- Uplink/downlink işleme: `pkg/networkserver/grpc_gsns.go:1493`
- MAC command handling: `pkg/networkserver/mac/`
- Device state (Redis): `pkg/networkserver/redis/`

### Application Server (AS)
- Uplink processing: `pkg/applicationserver/grpc.go:133`
- Payload decode: `pkg/applicationserver/payload.go:119`
- Output integrations: `pkg/applicationserver/io/`

### Gateway Server (GS)
- UDP Packet Forwarder: `pkg/gatewayserver/io/udp/`
- BasicStation (WebSocket): `pkg/gatewayserver/io/semtechws/`
- MQTT protocol: `pkg/gatewayserver/io/mqtt/`

### Identity Server (IS)
- User/org management: `pkg/identityserver/`
- Entity registry: `pkg/identityserver/store/`
- OAuth2 provider: `pkg/identityserver/oauth/`

### Join Server (JS)
- OTAA handling: `pkg/joinserver/`
- Session key management: `pkg/joinserver/redis/`

## Data Flow

```
Device → Gateway → GatewayServer → NetworkServer → ApplicationServer → Integration
                        ↓                ↓
                   JoinServer      IdentityServer
```

## Kullanım

Bu skills Claude Code tarafından otomatik olarak okunur ve projeyle çalışırken context sağlar. Her skill dosyası:

1. **Overview**: Kapsamın kısa açıklaması
2. **Key Concepts**: Temel kavramlar
3. **Common Tasks**: Sık yapılan işlemler için adım adım rehberler
4. **Code Patterns**: Projede kullanılan pattern örnekleri
5. **Configuration Reference**: İlgili config parametreleri
6. **File References**: Kritik dosya yolları
7. **Troubleshooting**: Yaygın sorunlar ve çözümler

içerir.
