# The Things Stack - Claude Code Skills

This directory contains skill files that provide domain knowledge for Claude Code when working with The Things Stack (TTS) project.

## Skills List

| Skill | Description | Usage Area |
|-------|-------------|------------|
| [api-usage](./api-usage/SKILL.md) | gRPC/REST API usage | API integration, client development |
| [device-management](./device-management/SKILL.md) | End device lifecycle management | Device provisioning, OTAA/ABP |
| [gateway-management](./gateway-management/SKILL.md) | Gateway configuration | Gateway setup, protocols |
| [lorawan-protocol](./lorawan-protocol/SKILL.md) | LoRaWAN protocol implementation | MAC commands, class operations |
| [stack-internals](./stack-internals/SKILL.md) | Stack internal architecture | Component interaction, request flow |
| [database-operations](./database-operations/SKILL.md) | Database management | PostgreSQL, Redis, migrations |
| [performance-optimization](./performance-optimization/SKILL.md) | Performance tuning | Optimization, scaling |
| [troubleshooting](./troubleshooting/SKILL.md) | Troubleshooting | Debug, log analysis |

## Project Structure

```
lorawan-stack/
├── api/ttn/lorawan/v3/          # Proto definitions (58 files)
├── pkg/
│   ├── networkserver/           # Network Server implementation
│   │   ├── grpc_gsns.go         # GS-NS gRPC handler
│   │   └── mac/                 # MAC command handlers (50+ files)
│   ├── applicationserver/       # Application Server implementation
│   │   ├── grpc.go              # NS-AS gRPC handler
│   │   └── io/                  # Output integrations (mqtt, web, pubsub)
│   ├── gatewayserver/           # Gateway Server implementation
│   │   └── io/                  # Gateway protocols (udp, semtechws, mqtt)
│   ├── identityserver/          # Identity Server (auth, registry)
│   │   └── store/migrations/    # Database migrations
│   └── joinserver/              # Join Server (OTAA key management)
├── data/lorawan-frequency-plans/ # Frequency plan definitions
└── deploy/olivenet/             # Deployment configuration
```

## Main Components

### Network Server (NS)
- Uplink/downlink processing: `pkg/networkserver/grpc_gsns.go:1493`
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

## Usage

These skills are automatically read by Claude Code and provide context when working with the project. Each skill file contains:

1. **Overview**: Brief description of scope
2. **Key Concepts**: Fundamental concepts
3. **Common Tasks**: Step-by-step guides for common operations
4. **Code Patterns**: Pattern examples used in the project
5. **Configuration Reference**: Related config parameters
6. **File References**: Critical file paths
7. **Troubleshooting**: Common issues and solutions
