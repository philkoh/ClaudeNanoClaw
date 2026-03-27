#!/bin/bash
# Tier 3 user-data script — runs as root on first boot via cloud-init
# NOTE: cloud-init runs this with /bin/sh by default; we use #!/bin/bash above
# but avoid pipefail since some cloud-init wrappers may still use dash
set -eu

TIER1_IP="174.129.11.27"
TIER1_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBDpWjTKSaxwJstOcsY8tAiZ/D4M2ojViy5eE2HkZOL5 tier1-to-tier3"

# Wait for cloud-init to finish so authorized_keys is set up
cloud-init status --wait || true

# [1] Add Tier 1 SSH key to authorized_keys
echo "$TIER1_PUBKEY" >> /home/ubuntu/.ssh/authorized_keys
chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
chmod 600 /home/ubuntu/.ssh/authorized_keys

# [2] SSH hardening (do NOT set UsePAM no — it breaks things on Ubuntu 24.04)
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh

# [3] UFW firewall
apt-get update -qq
apt-get install -y -qq ufw > /dev/null 2>&1
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow in from ${TIER1_IP} to any port 22 comment 'SSH from Tier 1 only'
ufw --force enable

# [4] Install Node.js 22 LTS via NodeSource
apt-get install -y -qq ca-certificates curl gnupg > /dev/null 2>&1
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list > /dev/null
apt-get update -qq
apt-get install -y -qq nodejs > /dev/null 2>&1

# [5] Install Gemini tooling
npm install -g @google/generative-ai 2>/dev/null || true

# [6] Prepare Gemini config
mkdir -p /home/ubuntu/.config/gemini
cat > /home/ubuntu/.config/gemini/config.json << 'GEMCONF'
{
  "model": "gemini-2.5-pro",
  "api_key_env": "GEMINI_API_KEY",
  "grounding": {
    "google_search": true
  },
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

# [7] Create env template (no secrets)
cat > /home/ubuntu/.env.template << 'ENVTEMPLATE'
# Tier 3 Environment Variables — DO NOT store actual secrets here.
# Tier 1 will inject these via SSH at runtime.
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

# [8] Email config docs
mkdir -p /home/ubuntu/email-config
cat > /home/ubuntu/email-config/README.txt << 'EMAILREADME'
EMAIL CONFIGURATION FOR TIER 3
===============================
Tier 3 needs READ-ONLY IMAP access to Exchange and Gmail.
Credentials are injected by Tier 1 at runtime via SSH env vars.
See .env.template for the variables Tier 1 will set.

For Exchange: App Password with IMAP read-only scope, outlook.office365.com:993
For Gmail: App Password (2FA required), imap.gmail.com:993
EMAILREADME
chown -R ubuntu:ubuntu /home/ubuntu/email-config

# [9] Disable unnecessary services
systemctl disable --now snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null || true
systemctl disable --now amazon-ssm-agent 2>/dev/null || true
systemctl disable --now ModemManager 2>/dev/null || true
systemctl disable --now cups-browsed 2>/dev/null || true
systemctl disable --now avahi-daemon 2>/dev/null || true
systemctl disable --now apache2 2>/dev/null || true
systemctl disable --now nginx 2>/dev/null || true
apt-get remove -y -qq apache2 nginx 2>/dev/null || true

# [10] Create results directory
mkdir -p /home/ubuntu/results
chown ubuntu:ubuntu /home/ubuntu/results

# Signal completion
echo "TIER3_PROVISIONING_COMPLETE" > /home/ubuntu/provisioning_done
chown ubuntu:ubuntu /home/ubuntu/provisioning_done
