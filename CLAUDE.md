# The Things Stack - Olivenet Ltd. Context

## Project Overview
The Things Stack (TTS) is an open-source LoRaWAN Network Server. This deployment is customized for **Olivenet**, a North Cyprus-based Industrial IoT company.

## Quick Reference

### Tech Stack
- **Language**: Go 1.24 (toolchain go1.24.1)
- **Frontend**: React (Console UI)
- **Database**: PostgreSQL 14+ (Identity Server), Redis 7+ (Cache/Sessions)
- **Build**: Mage
- **API**: gRPC with grpc-gateway (REST)

### Critical Directories
```
pkg/                    # Core Go packages
├── identityserver/     # User, org, app, gateway, device management
├── gatewayserver/      # Gateway connections (UDP, BasicStation, MQTT)
├── networkserver/      # LoRaWAN MAC layer, ADR, scheduling
├── applicationserver/  # Uplink/downlink routing, webhooks, pubsub
├── joinserver/         # OTAA join handling, key derivation
└── console/            # Web console backend

api/                    # Protocol Buffer definitions (50+ proto files)
cmd/                    # CLI entrypoints (ttn-lw-stack, ttn-lw-cli)
config/                 # Configuration templates
data/                   # Frequency plans, lorawan-devices database
```

### Key Files
| File | Purpose |
|------|---------|
| `pkg/networkserver/grpc_gsns.go` | Uplink handling entry point |
| `pkg/joinserver/joinserver.go` | OTAA join request processing |
| `pkg/gatewayserver/io/udp/udp.go` | UDP packet forwarder |
| `pkg/applicationserver/io/web/webhooks.go` | Webhook delivery |
| `go.mod` | Dependencies and Go version |
| `Dockerfile` | Container build (multi-stage, Alpine) |

## Build Commands

```bash
# Install dependencies
go mod download

# Build everything
mage go:build

# Build specific binary
mage go:buildStandalone ttn-lw-stack

# Run tests
mage go:test
mage js:test

# Generate code from protos
mage proto:all

# Start dev stack
mage dev:stack
```

## Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Console (UI)                            │
└─────────────────────────────────────────────────────────────────┘
                               │
┌─────────────────────────────────────────────────────────────────┐
│                    Identity Server (IS)                          │
│            Users, Organizations, Applications, Devices           │
│                      PostgreSQL Backend                          │
└─────────────────────────────────────────────────────────────────┘
                               │
     ┌─────────────────────────┼─────────────────────────┐
     │                         │                         │
┌────▼────┐              ┌─────▼─────┐             ┌─────▼─────┐
│ Gateway │              │  Network  │             │Application│
│ Server  │◄────────────►│  Server   │◄───────────►│  Server   │
│  (GS)   │              │   (NS)    │             │   (AS)    │
└────┬────┘              └─────┬─────┘             └─────┬─────┘
     │                         │                         │
     │                    ┌────▼────┐                    │
     │                    │  Join   │                    │
     │                    │ Server  │                    │
     │                    │  (JS)   │                    │
     │                    └─────────┘                    │
     │                                                   │
┌────▼────┐                                        ┌─────▼─────┐
│LoRaWAN  │                                        │  Webhooks │
│Gateways │                                        │  PubSub   │
└─────────┘                                        │  MQTT     │
                                                   └───────────┘
```

## Port Reference

| Port | Protocol | Service |
|------|----------|---------|
| 1700 | UDP | Gateway Packet Forwarder |
| 1881 | HTTP | OAuth Server |
| 8881 | HTTPS | OAuth Server (TLS) |
| 1882 | HTTP | Account App |
| 8882 | HTTPS | Account App (TLS) |
| 1883 | MQTT | MQTT Server |
| 8883 | MQTTS | MQTT Server (TLS) |
| 1884 | HTTP | Gateway Server HTTP |
| 8884 | HTTPS | Gateway Server HTTPS |
| 1885 | HTTP | Console/API |
| 8885 | HTTPS | Console/API (TLS) |
| 8887 | WSS | BasicStation Gateway |

## Database Schema (PostgreSQL)

```
accounts          # User accounts
organizations     # Organizations
applications      # Applications
end_devices       # Device registrations (EUIs, keys)
gateways          # Gateway registrations
api_keys          # API key storage
sessions          # User sessions
```

## Redis Keys (Prefixes)

```
ttn:v3:ns:devices:*     # Network Server device state
ttn:v3:as:devices:*     # Application Server device state
ttn:v3:gs:conn:*        # Gateway connections
ttn:v3:is:sessions:*    # User sessions
ttn:v3:tasks:*          # Async task queue
```

## Testing

```bash
# Unit tests
go test ./pkg/...

# Integration tests
go test ./pkg/... -tags=integration

# Frontend tests
yarn test

# E2E tests (Cypress)
yarn run cypress:ci
```

## Olivenet Customization Points

### Energy Meter Integration
1. **Payload Formatters**: `pkg/applicationserver/io/formatters/`
   - Create custom decoder for energy meter payloads
   - Support CayenneLPP or custom binary formats

2. **Webhooks**: Forward decoded data to ThingsBoard
   - Configure in Application settings
   - See `docs/olivenet/CUSTOMIZATION-ROADMAP.md`

3. **PubSub**: MQTT/NATS integration for real-time data
   - `pkg/applicationserver/io/pubsub/`

### Multi-tenant Setup
- Each customer = separate Organization
- Shared gateways via "Collaborator" permissions
- Rate limiting per tenant

## Deployment Files

```
deploy/olivenet/
├── docker-compose.yml      # Production stack
├── docker-compose.dev.yml  # Development stack
├── .env.example            # Environment template
├── config/
│   └── ttn-lw-stack.yml    # Stack configuration
├── scripts/
│   ├── deploy.sh           # Main deployment script
│   ├── health-check.sh     # System health monitoring
│   ├── preflight-check.sh  # Pre-deployment verification
│   ├── setup-services.sh   # Systemd service setup
│   ├── setup-tools.sh      # Python/simulator setup
│   ├── backup.sh           # Backup automation
│   ├── restore.sh          # Restore from backup
│   ├── validate.sh         # Installation validation
│   ├── monitor-daemon.sh   # Health monitoring daemon
│   └── alert.sh            # Alert notifications
└── simulator/              # LoRaWAN simulator tools
    ├── gateway_simulator.py
    ├── device_simulator.py
    ├── traffic_generator.py
    └── join_tester.py
```

## LoRaWAN Simulator

Python-based simulator for testing TTS without physical hardware.

### Quick Start
```bash
cd deploy/olivenet/simulator
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Test gateway connection
python gateway_simulator.py --test-only

# OTAA join test
python join_tester.py --dev-eui 70B3D57ED0000001 --app-key <key>

# Traffic load test (5000 devices)
python traffic_generator.py --scenario scenarios/stress_test.yml
```

### Simulator Tools
| Tool | Purpose |
|------|---------|
| `gateway_simulator.py` | Virtual gateway (Semtech UDP) |
| `device_simulator.py` | Virtual device (OTAA/ABP) |
| `join_tester.py` | Detailed OTAA join analysis |
| `traffic_generator.py` | Load testing (5000+ devices) |

See `docs/olivenet/SIMULATOR.md` for full documentation.

## Pre-Flight Check

Verify deployment readiness before starting the stack:

```bash
cd deploy/olivenet/scripts
./preflight-check.sh
```

### Check Categories
| Category | Checks |
|----------|--------|
| System | OS version, CPU, RAM, disk, swap |
| Docker | Installation, daemon, compose version |
| Network | Ports 1700/1885/8885, DNS, connectivity |
| Config | .env file, YAML syntax, TLS certs |
| Security | Password strength, secret length, permissions |

### Options
```bash
./preflight-check.sh --json           # JSON output
./preflight-check.sh --category network  # Single category
./preflight-check.sh --quick          # Fast mode
```

## Claude Code Commands

Custom commands for TTS management (`.claude/commands/`):

| Command | Description |
|---------|-------------|
| `/deploy` | Stack deployment procedures |
| `/status` | System status and health check |
| `/test` | Run tests (unit, integration, simulator) |
| `/backup` | Create backup |
| `/restore` | Restore from backup |
| `/logs` | View and filter logs |
| `/troubleshoot` | Diagnostic procedures |
| `/device` | End device management |
| `/gateway` | Gateway management |
| `/simulate` | Run simulator scenarios |

### Usage Example
```
User: /simulate traffic
Claude: [Runs traffic generator with default scenario]

User: /troubleshoot join
Claude: [Provides join failure diagnostic steps]
```

## Common Operations

### Register a Gateway
```bash
ttn-lw-cli gateways create my-gateway \
  --gateway-eui 0102030405060708 \
  --frequency-plan-id EU_863_870
```

### Register a Device (OTAA)
```bash
ttn-lw-cli end-devices create my-app my-device \
  --dev-eui 0102030405060708 \
  --app-eui 0102030405060708 \
  --app-key 01020304050607080102030405060708 \
  --lorawan-version 1.0.3 \
  --lorawan-phy-version 1.0.3-a
```

### View Uplink Traffic
```bash
ttn-lw-cli events subscribe --application-id my-app
```

## Security Notes

- All production traffic must use TLS (ports 88xx)
- Rotate API keys every 90 days
- Enable 2FA for admin accounts
- Review `SECURITY.md` for vulnerability reporting

## Related Documentation

- `docs/olivenet/ARCHITECTURE.md` - Detailed architecture
- `docs/olivenet/DEPLOYMENT.md` - Production deployment guide
- `docs/olivenet/DEVELOPMENT.md` - Development setup
- `docs/olivenet/CUSTOMIZATION-ROADMAP.md` - Olivenet-specific customizations
- `docs/olivenet/TROUBLESHOOTING.md` - Common issues and solutions
- `docs/olivenet/SIMULATOR.md` - LoRaWAN simulator usage guide
- `docs/olivenet/OPERATIONS.md` - Operational procedures
- `.claude/commands/README.md` - Claude Code commands reference

## Support

- **GitHub Issues**: https://github.com/TheThingsNetwork/lorawan-stack/issues
- **Documentation**: https://www.thethingsindustries.com/docs/
- **Forum**: https://www.thethingsnetwork.org/forum/
