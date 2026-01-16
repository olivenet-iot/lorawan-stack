# /deploy Command

Deploys or updates the TTS stack.

## Parameters

| Parameter | Description |
|-----------|-------------|
| --check | Only run preflight check |
| --dry-run | Show what would be done, don't execute |
| --force | Overwrite existing .env |
| --skip-oauth | Skip OAuth setup (for re-runs) |
| --no-backup | Don't create backup before update |

## Procedure

### Automated Deployment (Recommended)

The deploy.sh script handles all steps automatically:

```bash
cd /opt/lorawan-stack/deploy/olivenet
./scripts/deploy.sh
```

**The script does the following:**
1. Prompts for domain and email
2. TLS selection (Let's Encrypt / Self-signed / None)
3. Auto-generates all secrets
4. Creates .env file
5. Creates ACME directory (with correct permissions)
6. Starts databases
7. Runs migration
8. Creates admin user and OAuth clients
9. Fixes OAuth grants (critical!)
10. Starts the stack
11. Displays admin credentials

### Dry Run

To see what would happen without making changes:

```bash
./scripts/deploy.sh --dry-run
```

### Re-deployment

To restart existing deployment:

```bash
./scripts/deploy.sh --skip-oauth --force
```

### Manual Deployment

If you prefer manual deployment:

1. **Preflight Check**
```bash
./scripts/preflight-check.sh
```

2. **Environment Setup**
```bash
cp .env.example .env
nano .env  # Fill in values

# For secrets:
openssl rand -hex 32  # CONSOLE_OAUTH_CLIENT_SECRET
openssl rand -hex 16  # BLOCK_KEY
openssl rand -hex 32  # HASH_KEY
```

3. **ACME Directory**
```bash
mkdir -p acme
sudo chown 886:886 acme
```

4. **Start Database**
```bash
docker compose up -d postgres redis
sleep 15
```

5. **Migration**
```bash
docker compose run --rm stack is-db migrate
```

6. **Admin User**
```bash
docker compose run --rm stack is-db create-admin-user \
  --id admin \
  --email admin@yourdomain.com \
  --password <password>
```

7. **OAuth Clients**
```bash
# CLI client
docker compose run --rm stack is-db create-oauth-client \
  --id cli --name "CLI" --owner admin --no-secret \
  --redirect-uri "local-callback" --redirect-uri "code"

# Console client
docker compose run --rm stack is-db create-oauth-client \
  --id console --name "Console" --owner admin \
  --secret "${CONSOLE_OAUTH_CLIENT_SECRET}" \
  --redirect-uri "https://yourdomain.com/console/oauth/callback" \
  --logout-redirect-uri "https://yourdomain.com/console"
```

8. **OAuth Grants Fix (CRITICAL!)**
```bash
docker compose exec -T postgres psql -U ttn -d ttn_lorawan -c \
  "UPDATE clients SET grants = '{0,2}', skip_authorization = true, endorsed = true WHERE client_id = 'console';"
```

9. **Start Stack**
```bash
docker compose up -d stack
```

## Update

```bash
# Create backup
./scripts/backup.sh

# Update image
docker compose pull
docker compose up -d

# Migration (if needed)
docker compose run --rm stack is-db migrate
```

## Success Status

```
+================================================================+
|                   DEPLOYMENT COMPLETE                          |
+================================================================+

Console:  https://tts.olivenet.io/console

Admin Credentials
================================================================
  Username: admin
  Email:    admin@olivenet.io
  Password: ************

IMPORTANT: Change the admin password immediately after first login!
```

## Error States

| Error | Solution |
|-------|----------|
| Port in use | Find process with `ss -tlnp \| grep <port>` |
| Docker not running | `systemctl start docker` |
| ACME failed | Are DNS records correct? Is port 80 open? |
| OAuth error | Run grants fix SQL command |
| Migration failed | Check logs: `docker compose logs stack` |

## Critical Notes

⚠️ **OAuth Grants**: The grants fix SQL command is critical for Console login!
```sql
UPDATE clients SET grants = '{0,2}', skip_authorization = true, endorsed = true WHERE client_id = 'console';
```

⚠️ **ACME Permissions**: ACME directory must be owned by 886:886 (TTS container user)

⚠️ **Config Template**: To make changes:
- `config/ttn-lw-stack.yml.template` - Template file
- `config/ttn-lw-stack.yml` - Active config

## Related Commands

- `/status` - Check deployment status
- `/backup` - Create backup
- `/troubleshoot` - Troubleshooting
