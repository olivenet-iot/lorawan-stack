#!/bin/bash
# =============================================================================
# Olivenet TTS - Tools & Simulator Setup
# =============================================================================
# Installs Python, dependencies, and prepares testing environment
#
# Usage:
#   ./setup-tools.sh              # Interactive setup
#   ./setup-tools.sh --force      # Skip confirmation prompts
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
SIMULATOR_DIR="$DEPLOY_DIR/simulator"
VENV_DIR="$SIMULATOR_DIR/venv"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# =============================================================================
# Logging Functions
# =============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# =============================================================================
# Argument Parsing
# =============================================================================

FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force]"
            echo ""
            echo "Options:"
            echo "  -f, --force    Skip confirmation prompts"
            echo "  -h, --help     Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Banner
# =============================================================================

echo ""
echo -e "${BLUE}+================================================================+${NC}"
echo -e "${BLUE}|${NC}        ${BOLD}Olivenet TTS - Tools & Simulator Setup${NC}              ${BLUE}|${NC}"
echo -e "${BLUE}+================================================================+${NC}"
echo ""

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
else
    SUDO=""
fi

# =============================================================================
# Step 1: Install System Dependencies
# =============================================================================
log_info "Step 1/6: Installing system dependencies..."

if command -v apt-get &> /dev/null; then
    $SUDO apt-get update -qq || true
    $SUDO apt-get install -y -qq python3 python3-pip python3-venv mosquitto-clients curl jq > /dev/null 2>&1 || {
        log_warn "Some packages may not have installed. Continuing..."
    }
    log_ok "System dependencies installed (apt)"
elif command -v yum &> /dev/null; then
    $SUDO yum install -y -q python3 python3-pip mosquitto curl jq > /dev/null 2>&1 || true
    log_ok "System dependencies installed (yum)"
elif command -v dnf &> /dev/null; then
    $SUDO dnf install -y -q python3 python3-pip mosquitto curl jq > /dev/null 2>&1 || true
    log_ok "System dependencies installed (dnf)"
else
    log_warn "Could not detect package manager."
    log_warn "Please install manually: python3, python3-pip, python3-venv, mosquitto-clients, curl, jq"
fi

# =============================================================================
# Step 2: Verify Python
# =============================================================================
log_info "Step 2/6: Verifying Python installation..."

if ! command -v python3 &> /dev/null; then
    log_error "Python3 not found. Please install Python 3.8+"
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [[ $PYTHON_MAJOR -lt 3 ]] || [[ $PYTHON_MAJOR -eq 3 && $PYTHON_MINOR -lt 8 ]]; then
    log_error "Python 3.8+ required. Found: $PYTHON_VERSION"
    exit 1
fi

log_ok "Python $PYTHON_VERSION found"

# =============================================================================
# Step 3: Create Virtual Environment
# =============================================================================
log_info "Step 3/6: Creating Python virtual environment..."

if [[ -d "$VENV_DIR" ]]; then
    if [[ "$FORCE" == "true" ]]; then
        rm -rf "$VENV_DIR"
        python3 -m venv "$VENV_DIR"
        log_ok "Virtual environment recreated"
    else
        log_warn "Virtual environment already exists at $VENV_DIR"
        read -p "Recreate? [y/N]: " recreate
        if [[ "$recreate" =~ ^[Yy]$ ]]; then
            rm -rf "$VENV_DIR"
            python3 -m venv "$VENV_DIR"
            log_ok "Virtual environment recreated"
        else
            log_info "Using existing virtual environment"
        fi
    fi
else
    python3 -m venv "$VENV_DIR"
    log_ok "Virtual environment created at $VENV_DIR"
fi

# =============================================================================
# Step 4: Install Python Dependencies
# =============================================================================
log_info "Step 4/6: Installing Python dependencies..."

# Activate venv
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

# Upgrade pip
pip install --upgrade pip -q 2>/dev/null || pip install --upgrade pip

# Uninstall conflicting crypto packages first (crypto, pycrypto, Crypto)
pip uninstall -y crypto pycrypto Crypto 2>/dev/null || true

# Force reinstall pycryptodome to ensure clean installation
pip install --force-reinstall pycryptodome -q 2>/dev/null || pip install --force-reinstall pycryptodome
log_ok "pycryptodome installed"

# Install remaining requirements
if [[ -f "$SIMULATOR_DIR/requirements.txt" ]]; then
    pip install -r "$SIMULATOR_DIR/requirements.txt" -q 2>/dev/null || \
        pip install -r "$SIMULATOR_DIR/requirements.txt"
    log_ok "Python dependencies installed"
else
    log_error "requirements.txt not found at $SIMULATOR_DIR/requirements.txt"
    deactivate
    exit 1
fi

# =============================================================================
# Step 5: Set Permissions
# =============================================================================
log_info "Step 5/6: Setting file permissions..."

# Make scripts executable
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
log_ok "Scripts are executable"

# Make Python files executable
chmod +x "$SIMULATOR_DIR"/*.py 2>/dev/null || true
log_ok "Simulator files are executable"

# =============================================================================
# Step 6: Create Activation Script
# =============================================================================
log_info "Step 6/6: Creating activation helper..."

cat > "$SIMULATOR_DIR/activate.sh" << 'ACTIVATE_EOF'
#!/bin/bash
# =============================================================================
# Olivenet TTS Simulator - Environment Activation Helper
# =============================================================================
# Usage: source activate.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$SCRIPT_DIR/venv" ]]; then
    echo "Error: Virtual environment not found. Run setup-tools.sh first."
    return 1 2>/dev/null || exit 1
fi

source "$SCRIPT_DIR/venv/bin/activate"
cd "$SCRIPT_DIR"

echo ""
echo "Simulator environment activated"
echo ""
echo "Available commands:"
echo "  python3 gateway_simulator.py --help"
echo ""
echo "Quick test:"
echo "  python3 gateway_simulator.py --test-only"
echo ""
ACTIVATE_EOF

chmod +x "$SIMULATOR_DIR/activate.sh"
log_ok "Activation helper created"

# =============================================================================
# Verify Installation
# =============================================================================
log_info "Verifying installation..."

if python3 -c "
import sys
try:
    from Crypto.Cipher import AES
    from Crypto.Hash import CMAC
    import yaml
    import colorama
    print('All imports successful')
    sys.exit(0)
except ImportError as e:
    print(f'Import error: {e}')
    sys.exit(1)
"; then
    log_ok "All dependencies verified"
else
    log_error "Some dependencies failed to import"
    deactivate
    exit 1
fi

deactivate

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${GREEN}+================================================================+${NC}"
echo -e "${GREEN}|${NC}                    ${BOLD}SETUP COMPLETE${NC}                            ${GREEN}|${NC}"
echo -e "${GREEN}+================================================================+${NC}"
echo ""
echo -e "${CYAN}Installed Components:${NC}"
echo "  - Python $PYTHON_VERSION"
echo "  - Virtual environment: $VENV_DIR"
echo "  - Simulator dependencies (pycryptodome, pyyaml, requests, etc.)"
echo "  - mosquitto-clients (MQTT testing)"
echo "  - jq (JSON processing)"
echo ""
echo -e "${CYAN}Quick Start:${NC}"
echo ""
echo "  # Option 1: Use activation helper"
echo -e "  ${YELLOW}source $SIMULATOR_DIR/activate.sh${NC}"
echo ""
echo "  # Option 2: Manual activation"
echo "  cd $SIMULATOR_DIR"
echo "  source venv/bin/activate"
echo ""
echo -e "${CYAN}Example Commands:${NC}"
echo ""
echo "  # Gateway connectivity test"
echo -e "  ${YELLOW}python3 gateway_simulator.py --server localhost --port 1700 --test-only${NC}"
echo ""
echo "  # Interactive gateway session"
echo -e "  ${YELLOW}python3 gateway_simulator.py --server localhost --port 1700 --interactive${NC}"
echo ""
echo "  # MQTT subscription test"
echo -e "  ${YELLOW}mosquitto_sub -h localhost -p 1883 -t 'v3/+/devices/+/up' -d${NC}"
echo ""
