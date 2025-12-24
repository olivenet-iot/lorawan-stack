# GitHub Secrets Configuration

This document explains the GitHub secrets required for Olivenet TTS CI/CD pipelines to work.

## Required Secrets

### Deployment Secrets (Required)

| Secret | Description | Example |
|--------|-------------|---------|
| `DEPLOY_SSH_KEY` | Server SSH private key | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `DEPLOY_HOST` | Server IP or hostname | `192.168.1.100` or `tts.olivenet.com` |
| `DEPLOY_USER` | SSH username | `deploy` or `ubuntu` |

### Notification Secrets (Optional)

| Secret | Description | Example |
|--------|-------------|---------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot API token | `123456789:ABCdefGHIjklMNOpqrsTUVwxyz` |
| `TELEGRAM_CHAT_ID` | Telegram chat/group ID | `-1001234567890` |

---

## Creating Secrets

### 1. Creating SSH Key

Create an SSH key pair for server access:

```bash
# Create new SSH key
ssh-keygen -t ed25519 -C "github-deploy@olivenet" -f ~/.ssh/github_deploy

# Add public key to server
ssh-copy-id -i ~/.ssh/github_deploy.pub deploy@server-ip

# Private key content (for DEPLOY_SSH_KEY)
cat ~/.ssh/github_deploy
```

**Important Notes:**
- Do not use a passphrase (leave empty)
- Copy the entire private key (everything between `-----BEGIN` and `-----END`)
- Ensure the public key is added to `/home/deploy/.ssh/authorized_keys` on the server

### 2. Creating Deploy User

Create a dedicated deploy user on the server:

```bash
# Create user
sudo useradd -m -s /bin/bash deploy

# Add to docker group
sudo usermod -aG docker deploy

# Grant access to deployment directory
sudo chown -R deploy:deploy /opt/olivenet-tts

# Create SSH directory
sudo -u deploy mkdir -p /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
```

### 3. Creating Telegram Bot

1. Chat with [@BotFather](https://t.me/BotFather) on Telegram
2. Create a new bot with the `/newbot` command
3. Enter the bot name and username
4. Save the API token as `TELEGRAM_BOT_TOKEN`

To get the Chat ID:
```bash
# Add the bot to a group, then:
curl "https://api.telegram.org/bot<TOKEN>/getUpdates"
# Use the chat.id value from the response
```

---

## Adding Secrets to GitHub

### Repository Secrets

1. Go to your GitHub repository
2. **Settings** > **Secrets and variables** > **Actions**
3. Click **New repository secret**
4. Enter the secret name and value

### Environment Secrets

To use separate secrets for production and staging:

1. **Settings** > **Environments**
2. Create `staging` and `production` environments
3. Add separate secrets for each environment

---

## Secret References

### ci.yml
```yaml
# Does not require any secrets
# Optional: CODECOV_TOKEN (for coverage upload)
```

### deploy.yml
```yaml
secrets:
  - DEPLOY_SSH_KEY      # Required
  - DEPLOY_HOST         # Required
  - DEPLOY_USER         # Required
  - TELEGRAM_BOT_TOKEN  # Optional
  - TELEGRAM_CHAT_ID    # Optional
```

### release.yml
```yaml
secrets:
  - GITHUB_TOKEN        # Automatic (available in repository)
  - TELEGRAM_BOT_TOKEN  # Optional
  - TELEGRAM_CHAT_ID    # Optional
```

### scheduled.yml
```yaml
secrets:
  - DEPLOY_SSH_KEY      # For backup verification
  - DEPLOY_HOST         # For backup verification
  - DEPLOY_USER         # For backup verification
  - TELEGRAM_BOT_TOKEN  # For alerts
  - TELEGRAM_CHAT_ID    # For alerts
```

---

## Security Recommendations

1. **SSH Key Rotation**: Rotate SSH keys every 6 months
2. **Minimal Permissions**: Grant only necessary permissions to the deploy user
3. **IP Whitelist**: Whitelist GitHub Actions IPs on the server if possible
4. **Audit Logs**: Regularly check GitHub Actions logs
5. **Environment Protection**: Add protection rules for production environment

### Environment Protection Rules

Recommended for production environment:
- Required reviewers (at least 1 approval)
- Wait timer (5 minute wait)
- Deployment branches (main/master only)

```
Settings > Environments > production > Protection rules
```

---

## Troubleshooting

### SSH Connection Error

```
Error: ssh: connect to host xxx port 22: Connection refused
```

**Solution:**
1. Verify SSH service is running on the server
2. Open port 22 in the firewall
3. Verify `DEPLOY_HOST` value is correct

### Permission Denied

```
Error: Permission denied (publickey)
```

**Solution:**
1. Verify SSH key is in correct format
2. Check authorized_keys file on server
3. Check file permissions:
   ```bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```

### Telegram Notification Error

```
Error: Bad Request: chat not found
```

**Solution:**
1. Ensure the bot is added to the group
2. Verify Chat ID is correct (group IDs start with negative numbers)
3. Verify the bot has permission to send messages
