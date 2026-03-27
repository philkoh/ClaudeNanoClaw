#!/bin/bash
# provision_tier3_v2.sh — OpenClaw Tier 3 provisioning (runs ON Tier 3 via sudo)
set -eu

TIER1_IP="174.129.11.27"

echo "=== [1/8] SSH Hardening ==="
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart ssh
echo "SSH hardened."

echo "=== [2/8] UFW Firewall ==="
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw > /dev/null 2>&1
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in from ${TIER1_IP} to any port 22 comment 'SSH from Tier 1 only'
sudo ufw --force enable
echo "UFW enabled."
sudo ufw status verbose

echo "=== [3/8] Install Node.js 22 LTS via NodeSource ==="
sudo apt-get install -y -qq ca-certificates curl gnupg > /dev/null 2>&1
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs > /dev/null 2>&1
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

echo "=== [4/8] Install Gemini tooling ==="
sudo npm install -g @google/generative-ai 2>/dev/null || true
echo "Installed global npm packages:"
npm list -g --depth=0 2>/dev/null || true

echo "=== [5/8] Prepare Gemini configuration ==="
mkdir -p /home/ubuntu/.config/gemini
cat > /home/ubuntu/.config/gemini/config.json << 'GEMCONF'
{
  "model": "gemini-2.5-pro",
  "api_key_env": "GEMINI_API_KEY",
  "grounding": { "google_search": true },
  "output": {
    "max_summary_length": 500,
    "max_search_result_length": 300,
    "format": "plain_text"
  },
  "safety": {
    "system_prompt_note": "Output ONLY plain-text summaries. No raw HTML, no URLs longer than necessary, no quoted text longer than one sentence."
  }
}
GEMCONF
chown -R ubuntu:ubuntu /home/ubuntu/.config/gemini

cat > /home/ubuntu/.env.template << 'ENVTEMPLATE'
# Tier 3 Environment Variables — Tier 1 injects these via SSH at runtime.
# GEMINI_API_KEY=
# EXCHANGE_IMAP_HOST=outlook.office365.com
# EXCHANGE_IMAP_PORT=993
# EXCHANGE_IMAP_USER=
# EXCHANGE_IMAP_PASSWORD=
# GMAIL_IMAP_HOST=imap.gmail.com
# GMAIL_IMAP_PORT=993
# GMAIL_IMAP_USER=
# GMAIL_IMAP_PASSWORD=
ENVTEMPLATE
chown ubuntu:ubuntu /home/ubuntu/.env.template

echo "=== [6/8] Email config templates ==="
mkdir -p /home/ubuntu/email-config
cat > /home/ubuntu/email-config/README.txt << 'EMAILREADME'
EMAIL CONFIGURATION FOR TIER 3
Tier 3 needs READ-ONLY IMAP access to Exchange and Gmail.
Credentials are injected by Tier 1 at runtime via SSH env vars.
Exchange: App Password, outlook.office365.com:993 (SSL/TLS)
Gmail: App Password (2FA required), imap.gmail.com:993 (SSL/TLS)
EMAILREADME
chown -R ubuntu:ubuntu /home/ubuntu/email-config

echo "=== [7/8] Disable unnecessary services ==="
sudo systemctl disable --now snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null || true
sudo systemctl disable --now amazon-ssm-agent 2>/dev/null || true
sudo systemctl disable --now ModemManager 2>/dev/null || true
sudo systemctl disable --now cups-browsed 2>/dev/null || true
sudo systemctl disable --now avahi-daemon 2>/dev/null || true
sudo systemctl disable --now apache2 2>/dev/null || true
sudo systemctl disable --now nginx 2>/dev/null || true
sudo apt-get remove -y -qq apache2 nginx 2>/dev/null || true
echo "Unnecessary services disabled."

echo "=== [8/8] Create results directory ==="
mkdir -p /home/ubuntu/results
chown ubuntu:ubuntu /home/ubuntu/results

echo ""
echo "=== Tier 3 provisioning complete ==="
