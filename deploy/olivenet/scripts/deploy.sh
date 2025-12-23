#!/bin/bash
# =============================================================================
# Olivenet TTS Production Deployment Script
# =============================================================================
# Automated deployment for The Things Stack
#
# Usage:
#   ./deploy.sh                    # Interactive deployment
#   ./deploy.sh --dry-run          # Show what would be done
#   ./deploy.sh --force            # Overwrite existing .env
#   ./deploy.sh --skip-oauth       # Skip OAuth setup (for re-runs)
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${DEPLOY_DIR}/config"

# =============================================================================
# Colors and Output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Arguments
# =============================================================================
DRY_RUN=false
FORCE=false
SKIP_OAUTH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --skip-oauth)
            SKIP_OAUTH=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run      Show what would be done without making changes"
            echo "  --force        Overwrite existing .env file"
            echo "  --skip-oauth   Skip OAuth client setup (for re-runs)"
            echo "  -h, --help     Show this help message"
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
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}           ${BLUE}Olivenet TTS Production Deployment${NC}                  ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY RUN MODE - No changes will be made"
    echo ""
fi

# =============================================================================
# Check Prerequisites
# =============================================================================
log_info "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    log_error "Docker Compose V2 is not installed"
    exit 1
fi

if ! command -v openssl &> /dev/null; then
    log_error "OpenSSL is not installed"
    exit 1
fi

log_success "Prerequisites check passed"

# =============================================================================
# Check for existing deployment
# =============================================================================
if [[ -f "${DEPLOY_DIR}/.env" ]] && [[ "$FORCE" != "true" ]]; then
    log_warn ".env file already exists"
    read -p "Overwrite existing configuration? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "Use --force to overwrite or --skip-oauth to just restart services"
        exit 0
    fi
fi

# =============================================================================
# Get User Input
# =============================================================================
echo ""
echo -e "${YELLOW}Configuration${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Domain
while [[ -z "$DOMAIN" ]]; do
    read -p "Enter domain name (e.g., tts.olivenet.io): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        log_error "Domain cannot be empty"
    fi
done

# Email
DEFAULT_EMAIL="admin@${DOMAIN#*.}"
read -p "Enter admin/ACME email [${DEFAULT_EMAIL}]: " ACME_EMAIL
ACME_EMAIL=${ACME_EMAIL:-$DEFAULT_EMAIL}

# TLS Choice
echo ""
echo "TLS Configuration:"
echo "  1) Let's Encrypt (ACME) - Recommended for production"
echo "  2) Self-signed certificate"
echo "  3) No TLS (HTTP only) - For testing only"
read -p "Select TLS option [1]: " TLS_CHOICE
TLS_CHOICE=${TLS_CHOICE:-1}

case $TLS_CHOICE in
    1) TLS_SOURCE="acme" ;;
    2) TLS_SOURCE="file" ;;
    3) TLS_SOURCE="" ;;
    *) log_error "Invalid TLS option"; exit 1 ;;
esac

# Confirm
echo ""
echo -e "${YELLOW}Configuration Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Domain:     ${DOMAIN}"
echo "  Email:      ${ACME_EMAIL}"
echo "  TLS:        ${TLS_SOURCE:-none}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN - Would proceed with above configuration"
    exit 0
fi

read -p "Proceed with deployment? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    log_info "Deployment cancelled"
    exit 0
fi

# =============================================================================
# Generate Secrets
# =============================================================================
echo ""
log_info "Generating secrets..."

POSTGRES_PASS=$(openssl rand -hex 16)
REDIS_PASS=$(openssl rand -hex 16)
ADMIN_PASS=$(openssl rand -base64 12 | tr -d '/+=')
CONSOLE_SECRET=$(openssl rand -hex 32)
DEVICE_CLAIMING_SECRET=$(openssl rand -hex 32)
HASH_KEY=$(openssl rand -hex 32)
BLOCK_KEY=$(openssl rand -hex 16)

log_success "Secrets generated"

# =============================================================================
# Create .env File
# =============================================================================
log_info "Creating .env file..."

cat > "${DEPLOY_DIR}/.env" << EOF
# =============================================================================
# Olivenet TTS - Production Environment
# Generated: $(date -Iseconds)
# Domain: ${DOMAIN}
# =============================================================================

# -----------------------------------------------------------------------------
# Domain Configuration
# -----------------------------------------------------------------------------
DOMAIN=${DOMAIN}
CLUSTER_ID=olivenet-tts

# -----------------------------------------------------------------------------
# Database (PostgreSQL)
# -----------------------------------------------------------------------------
POSTGRES_USER=ttn
POSTGRES_PASSWORD=${POSTGRES_PASS}
POSTGRES_DB=ttn_lorawan
POSTGRES_SHARED_BUFFERS=256MB

# -----------------------------------------------------------------------------
# Cache (Redis)
# -----------------------------------------------------------------------------
REDIS_PASSWORD=${REDIS_PASS}
REDIS_MAXMEMORY=512mb

# -----------------------------------------------------------------------------
# TLS Configuration
# -----------------------------------------------------------------------------
TLS_SOURCE=${TLS_SOURCE}
ACME_EMAIL=${ACME_EMAIL}
ACME_DIR=/var/lib/acme

# -----------------------------------------------------------------------------
# LoRaWAN Network
# -----------------------------------------------------------------------------
NET_ID=000000
DEV_ADDR_PREFIX=26000000/7

# -----------------------------------------------------------------------------
# OAuth Secrets
# -----------------------------------------------------------------------------
CONSOLE_OAUTH_CLIENT_SECRET=${CONSOLE_SECRET}
DEVICE_CLAIMING_SECRET=${DEVICE_CLAIMING_SECRET}

# -----------------------------------------------------------------------------
# Cookie Keys
# -----------------------------------------------------------------------------
HASH_KEY=${HASH_KEY}
BLOCK_KEY=${BLOCK_KEY}

# -----------------------------------------------------------------------------
# SMTP (Optional - configure for email notifications)
# -----------------------------------------------------------------------------
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM=noreply@${DOMAIN}

# -----------------------------------------------------------------------------
# Ports
# -----------------------------------------------------------------------------
HTTP_PORT=80
HTTPS_PORT=443
GS_UDP_PORT=1700
GS_MQTT_PORT=8883
GS_BASICSTATION_PORT=8887

# -----------------------------------------------------------------------------
# Application Server
# -----------------------------------------------------------------------------
WEBHOOK_QUEUE_SIZE=1000
WEBHOOK_WORKERS=16

# -----------------------------------------------------------------------------
# Blob Storage
# -----------------------------------------------------------------------------
BLOB_LOCAL_DIRECTORY=/srv/ttn-lorawan/public/blob

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
LOG_LEVEL=info
LOG_FORMAT=json

# -----------------------------------------------------------------------------
# Metrics
# -----------------------------------------------------------------------------
METRICS_ENABLED=true
PPROF_ENABLED=false

# -----------------------------------------------------------------------------
# Resource Limits
# -----------------------------------------------------------------------------
STACK_MEMORY_LIMIT=4g
EOF

chmod 600 "${DEPLOY_DIR}/.env"
log_success ".env file created"

# =============================================================================
# Generate Config from Template
# =============================================================================
log_info "Generating stack configuration..."

if [[ -f "${CONFIG_DIR}/ttn-lw-stack.yml.template" ]]; then
    # Use template if available
    sed -e "s/\${DOMAIN}/${DOMAIN}/g" \
        -e "s/\${ACME_EMAIL}/${ACME_EMAIL}/g" \
        -e "s/\${TLS_SOURCE}/${TLS_SOURCE}/g" \
        -e "s/\${CONSOLE_OAUTH_CLIENT_SECRET}/${CONSOLE_SECRET}/g" \
        -e "s/\${DEVICE_CLAIMING_SECRET}/${DEVICE_CLAIMING_SECRET}/g" \
        "${CONFIG_DIR}/ttn-lw-stack.yml.template" > "${CONFIG_DIR}/ttn-lw-stack.yml.generated"
    log_success "Configuration generated from template"
else
    log_warn "Template not found, using existing config"
fi

# =============================================================================
# Create ACME Directory
# =============================================================================
if [[ "$TLS_SOURCE" == "acme" ]]; then
    log_info "Creating ACME directory..."
    mkdir -p "${DEPLOY_DIR}/acme"

    # TTS container runs as user 886
    if sudo chown 886:886 "${DEPLOY_DIR}/acme" 2>/dev/null; then
        log_success "ACME directory created with correct permissions"
    else
        log_warn "Could not set ACME directory ownership (may need sudo)"
        log_warn "Run: sudo chown 886:886 ${DEPLOY_DIR}/acme"
    fi
fi

# =============================================================================
# Start Database Services
# =============================================================================
echo ""
log_info "Starting database services..."
cd "${DEPLOY_DIR}"

docker compose up -d postgres redis

log_info "Waiting for databases to initialize (15 seconds)..."
sleep 15

# Check database health
if docker compose exec -T postgres pg_isready -U ttn &>/dev/null; then
    log_success "PostgreSQL is ready"
else
    log_error "PostgreSQL is not ready"
    exit 1
fi

if docker compose exec -T redis redis-cli -a "${REDIS_PASS}" PING &>/dev/null; then
    log_success "Redis is ready"
else
    log_error "Redis is not ready"
    exit 1
fi

# =============================================================================
# Run Database Migration
# =============================================================================
log_info "Running database migration..."
docker compose run --rm stack is-db migrate

log_success "Database migration completed"

# =============================================================================
# OAuth Setup
# =============================================================================
if [[ "$SKIP_OAUTH" != "true" ]]; then
    echo ""
    log_info "Setting up OAuth clients..."

    # Create admin user
    log_info "Creating admin user..."
    docker compose run --rm stack is-db create-admin-user \
        --id admin \
        --email "${ACME_EMAIL}" \
        --password "${ADMIN_PASS}" || log_warn "Admin user may already exist"

    # Create CLI OAuth client
    log_info "Creating CLI OAuth client..."
    docker compose run --rm stack is-db create-oauth-client \
        --id cli \
        --name "Command Line Interface" \
        --owner admin \
        --no-secret \
        --redirect-uri "local-callback" \
        --redirect-uri "code" || log_warn "CLI client may already exist"

    # Determine protocol
    if [[ "$TLS_SOURCE" == "acme" ]] || [[ "$TLS_SOURCE" == "file" ]]; then
        PROTOCOL="https"
    else
        PROTOCOL="http"
    fi

    # Create Console OAuth client
    log_info "Creating Console OAuth client..."
    docker compose run --rm stack is-db create-oauth-client \
        --id console \
        --name "Console" \
        --owner admin \
        --secret "${CONSOLE_SECRET}" \
        --redirect-uri "${PROTOCOL}://${DOMAIN}/console/oauth/callback" \
        --redirect-uri "/console/oauth/callback" \
        --logout-redirect-uri "${PROTOCOL}://${DOMAIN}/console" \
        --logout-redirect-uri "/console" || log_warn "Console client may already exist"

    # Fix OAuth grants (CRITICAL!)
    log_info "Fixing OAuth grants..."
    source "${DEPLOY_DIR}/.env"
    docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c \
        "UPDATE clients SET grants = '{0,2}', skip_authorization = true, endorsed = true WHERE client_id = 'console';" || true

    log_success "OAuth setup completed"
else
    log_info "Skipping OAuth setup (--skip-oauth)"
fi

# =============================================================================
# Start Stack
# =============================================================================
echo ""
log_info "Starting The Things Stack..."
docker compose up -d stack

# Wait for TLS certificate
if [[ "$TLS_SOURCE" == "acme" ]]; then
    log_info "Waiting for Let's Encrypt certificate (60 seconds)..."
    sleep 60
else
    log_info "Waiting for stack to initialize (20 seconds)..."
    sleep 20
fi

# =============================================================================
# Health Check
# =============================================================================
log_info "Running health check..."

if docker compose exec -T stack curl -sf http://localhost:1885/healthz &>/dev/null; then
    log_success "Stack is healthy"
else
    log_warn "Stack health check failed - may still be starting"
fi

# =============================================================================
# Success Banner
# =============================================================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                   ${GREEN}DEPLOYMENT COMPLETE${NC}                         ${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "$TLS_SOURCE" == "acme" ]] || [[ "$TLS_SOURCE" == "file" ]]; then
    CONSOLE_URL="https://${DOMAIN}/console"
else
    CONSOLE_URL="http://${DOMAIN}:1885/console"
fi

echo -e "Console:  ${BLUE}${CONSOLE_URL}${NC}"
echo ""
echo -e "${YELLOW}Admin Credentials${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Username: admin"
echo "  Email:    ${ACME_EMAIL}"
echo "  Password: ${ADMIN_PASS}"
echo ""
echo -e "${RED}IMPORTANT: Change the admin password immediately after first login!${NC}"
echo ""
echo -e "${YELLOW}Next Steps${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  1. Access the Console and login"
echo "  2. Change admin password"
echo "  3. Create an Application"
echo "  4. Register your first Gateway"
echo "  5. Add end devices"
echo ""
echo -e "${CYAN}For troubleshooting: ./scripts/health-check.sh${NC}"
echo ""
