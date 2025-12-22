# The Things Stack - Development Guide (Olivenet)

## Overview

This guide covers setting up a development environment for customizing The Things Stack for Olivenet's energy meter infrastructure.

## Prerequisites

### Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| Go | 1.24+ | Backend development |
| Node.js | 18+ | Frontend development |
| PostgreSQL | 14+ | Database |
| Redis | 7+ | Cache |
| Make | - | Build automation |
| Docker | 20.10+ | Containerization |

### Install Dependencies (Ubuntu/Debian)

```bash
# Go 1.24
wget https://go.dev/dl/go1.24.1.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.24.1.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# PostgreSQL and Redis
sudo apt-get install -y postgresql-14 redis-server

# Build tools
sudo apt-get install -y build-essential protobuf-compiler
```

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/TheThingsNetwork/lorawan-stack.git
cd lorawan-stack
```

### 2. Start Development Services

```bash
# Using Olivenet dev compose
cd deploy/olivenet
docker-compose -f docker-compose.dev.yml up -d postgres redis
```

### 3. Install Go Dependencies

```bash
go mod download
```

### 4. Install Node Dependencies

```bash
yarn install
```

### 5. Build and Run

```bash
# Build everything
mage go:build

# Or run in dev mode
mage dev:stack
```

## Build System (Mage)

Mage is the primary build tool. Common commands:

```bash
# List all available targets
mage -l

# Go commands
mage go:build              # Build all Go binaries
mage go:buildStandalone ttn-lw-stack  # Build specific binary
mage go:test               # Run Go tests
mage go:fmt                # Format Go code
mage go:lint               # Lint Go code

# JavaScript commands
mage js:build              # Build frontend
mage js:test               # Run JS tests
mage js:lint               # Lint JS code

# Protocol Buffers
mage proto:all             # Generate all proto code
mage proto:go              # Generate Go code only
mage proto:swagger         # Generate Swagger docs

# Development
mage dev:stack             # Start dev stack
mage dev:dbStart           # Start databases only
mage dev:dbStop            # Stop databases
```

## Project Structure

```
lorawan-stack/
├── api/                   # Protocol Buffer definitions
│   └── ttn/lorawan/v3/    # API v3 protos
├── cmd/                   # CLI entrypoints
│   ├── ttn-lw-stack/      # Main server
│   └── ttn-lw-cli/        # CLI client
├── config/                # Configuration templates
├── data/                  # Static data
│   ├── lorawan-devices/   # Device repository
│   └── frequency-plans/   # Regional plans
├── pkg/                   # Go packages
│   ├── identityserver/    # IS implementation
│   ├── gatewayserver/     # GS implementation
│   ├── networkserver/     # NS implementation
│   ├── applicationserver/ # AS implementation
│   ├── joinserver/        # JS implementation
│   ├── console/           # Console backend
│   └── webui/             # Frontend code
├── sdk/                   # Client SDKs
│   └── js/                # JavaScript SDK
├── tools/                 # Development tools
└── deploy/
    └── olivenet/          # Olivenet deployment
```

## Running Tests

### Go Tests

```bash
# All tests
mage go:test

# Specific package
go test ./pkg/networkserver/...

# With verbose output
go test -v ./pkg/applicationserver/io/web/...

# Integration tests
go test -tags=integration ./pkg/...

# Coverage
go test -coverprofile=coverage.out ./pkg/...
go tool cover -html=coverage.out
```

### Frontend Tests

```bash
# Jest tests
yarn test

# Watch mode
yarn test --watch

# Coverage
yarn test --coverage
```

### E2E Tests (Cypress)

```bash
# Start stack first
mage dev:stack

# Run Cypress
yarn cypress:open   # Interactive
yarn cypress:ci     # Headless
```

## Development Workflows

### Adding a New API Endpoint

1. **Define in Protocol Buffers**
```protobuf
// api/ttn/lorawan/v3/applicationserver.proto
service ApplicationServerEnergyMeter {
  rpc GetMeterReading(GetMeterReadingRequest) returns (MeterReading) {
    option (google.api.http) = {
      get: "/api/v3/as/meters/{device_id}/reading"
    };
  }
}
```

2. **Generate Code**
```bash
mage proto:all
```

3. **Implement Handler**
```go
// pkg/applicationserver/energy_meter.go
func (as *ApplicationServer) GetMeterReading(
    ctx context.Context,
    req *ttnpb.GetMeterReadingRequest,
) (*ttnpb.MeterReading, error) {
    // Implementation
}
```

4. **Register Service**
```go
// pkg/applicationserver/applicationserver.go
func (as *ApplicationServer) RegisterServices(s *grpc.Server) {
    ttnpb.RegisterApplicationServerEnergyMeterServer(s, as)
}
```

### Creating a Payload Formatter

1. **JavaScript Formatter**
```javascript
// For energy meter data
function decodeUplink(input) {
  var data = {};
  // Bytes: [voltage_h, voltage_l, current_h, current_l, power_h, power_l]
  data.voltage = (input.bytes[0] << 8 | input.bytes[1]) / 10;
  data.current = (input.bytes[2] << 8 | input.bytes[3]) / 1000;
  data.power = (input.bytes[4] << 8 | input.bytes[5]);
  return {
    data: data,
    warnings: [],
    errors: []
  };
}
```

2. **Test Locally**
```bash
# Use the formatter simulator
curl -X POST http://localhost:1885/api/v3/as/applications/test/packages/payload-formatters/formatters/simulate \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "uplink": {
      "f_port": 1,
      "frm_payload": "ARcAZABQ"
    },
    "formatter": "FORMATTER_JAVASCRIPT",
    "formatter_parameter": "function decodeUplink(input) { ... }"
  }'
```

### Adding a Webhook Integration

```go
// pkg/applicationserver/io/web/webhooks.go
// Custom webhook sink for ThingsBoard

type thingsboardSink struct {
    client *http.Client
    url    string
}

func (s *thingsboardSink) SendUplink(ctx context.Context, msg *ttnpb.ApplicationUp) error {
    // Transform to ThingsBoard format
    tbPayload := transformToThingsBoard(msg)

    req, _ := http.NewRequestWithContext(ctx, "POST", s.url, bytes.NewReader(tbPayload))
    req.Header.Set("Content-Type", "application/json")

    resp, err := s.client.Do(req)
    // Handle response
}
```

## Debugging

### VS Code Configuration

```json
// .vscode/launch.json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Stack",
      "type": "go",
      "request": "launch",
      "mode": "debug",
      "program": "${workspaceFolder}/cmd/ttn-lw-stack",
      "args": ["-c", "config/stack/ttn-lw-stack-docker.yml", "start"],
      "env": {
        "TTN_LW_LOG_LEVEL": "debug"
      }
    }
  ]
}
```

### Debugging Tips

```bash
# Enable debug logging
export TTN_LW_LOG_LEVEL=debug

# Trace gRPC calls
export GRPC_GO_LOG_VERBOSITY_LEVEL=99
export GRPC_GO_LOG_SEVERITY_LEVEL=info

# Profile CPU
go tool pprof http://localhost:1885/debug/pprof/profile?seconds=30

# Profile memory
go tool pprof http://localhost:1885/debug/pprof/heap
```

### Log Analysis

```bash
# Filter by component
docker-compose logs stack 2>&1 | grep "ns:"

# Filter by device
docker-compose logs stack 2>&1 | grep "dev_eui=0102030405060708"

# JSON log parsing
docker-compose logs stack 2>&1 | jq 'select(.namespace == "applicationserver")'
```

## Code Style

### Go Style Guide

```go
// Package comments
// Package networkserver implements the Network Server component.
package networkserver

// Interface naming
type DeviceRegistry interface {
    Get(ctx context.Context, ids *ttnpb.EndDeviceIdentifiers) (*ttnpb.EndDevice, error)
    Set(ctx context.Context, dev *ttnpb.EndDevice) (*ttnpb.EndDevice, error)
}

// Error handling
if err != nil {
    return nil, errInvalidDevice.WithCause(err).WithAttributes("dev_eui", devEUI)
}
```

### Proto Style

```protobuf
// Use clear field names
message EnergyMeterData {
  float voltage_volts = 1;
  float current_amps = 2;
  float power_watts = 3;
  google.protobuf.Timestamp measured_at = 4;
}
```

## Git Workflow

### Branch Naming

```
feature/olivenet-energy-meter-formatter
fix/webhook-retry-logic
docs/olivenet-deployment-guide
```

### Commit Messages

```
feat(as): add energy meter payload formatter

- Add JavaScript decoder for Olivenet meters
- Support voltage, current, power readings
- Add unit conversion helpers

Refs: OLIVENET-123
```

### Pull Request Checklist

- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] Proto regenerated (if API changed)
- [ ] Linting passes (`mage go:lint js:lint`)
- [ ] All tests pass (`mage go:test js:test`)

## Useful Commands

```bash
# Find where a function is defined
grep -rn "func.*HandleUplink" pkg/

# List all gRPC services
grep -rn "RegisterServer" pkg/

# Find all webhook implementations
find pkg/applicationserver -name "*.go" | xargs grep "webhook"

# Check import cycles
go list -f '{{.ImportPath}} {{.Imports}}' ./pkg/... | grep -E "cycle"

# Generate mocks
go generate ./pkg/...
```

## Olivenet Development Focus Areas

1. **Energy Meter Formatters**: `pkg/applicationserver/io/formatters/`
2. **Webhook Integration**: `pkg/applicationserver/io/web/`
3. **Device Provisioning**: `pkg/identityserver/store/`
4. **Gateway Management**: `pkg/gatewayserver/`

## Support Resources

- **Go Docs**: https://pkg.go.dev/go.thethings.network/lorawan-stack/v3
- **API Reference**: https://www.thethingsindustries.com/docs/reference/api/
- **GitHub Issues**: https://github.com/TheThingsNetwork/lorawan-stack/issues
