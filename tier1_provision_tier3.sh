#!/bin/bash
# provision_tier3.sh — Run ON Tier 1 to provision a fresh Tier 3 instance
# Assumes the instance already exists and has the Tier 1 ed25519 key in authorized_keys
set -eu

TIER3_IP="13.218.4.41"
TIER3_KEY="$HOME/.ssh/tier3_key"
TIER1_IP="174.129.11.27"

echo "[provision_tier3] Starting provisioning of Tier 3 at $TIER3_IP"

SSH_CMD="ssh -i $TIER3_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=15 ubuntu@$TIER3_IP"

# Wait for SSH to be available
echo "[provision_tier3] Waiting for SSH..."
for i in $(seq 1 30); do
    if $SSH_CMD "echo ok" > /dev/null 2>&1; then
        echo "[provision_tier3] SSH available after $i attempts."
        break
    fi
    sleep 10
done

# Run provisioning commands
echo "[provision_tier3] Hardening SSH..."
$SSH_CMD "sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && sudo systemctl restart ssh"

echo "[provision_tier3] Configuring UFW..."
$SSH_CMD "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw > /dev/null 2>&1 && sudo ufw --force reset && sudo ufw default deny incoming && sudo ufw default allow outgoing && sudo ufw allow in from $TIER1_IP to any port 22 comment 'SSH from Tier 1 only' && sudo ufw --force enable"

echo "[provision_tier3] Installing Node.js..."
$SSH_CMD "sudo apt-get install -y -qq ca-certificates curl gnupg > /dev/null 2>&1 && sudo mkdir -p /etc/apt/keyrings && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null; echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main' | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null && sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs > /dev/null 2>&1"

echo "[provision_tier3] Installing Gemini tooling..."
$SSH_CMD "sudo npm install -g @google/generative-ai 2>/dev/null || true"

echo "[provision_tier3] Creating config files..."
$SSH_CMD 'mkdir -p ~/.config/gemini ~/results ~/email-config'
$SSH_CMD 'cat > ~/.config/gemini/config.json << '\''EOF'\''
{"model":"gemini-2.5-pro","api_key_env":"GEMINI_API_KEY","grounding":{"google_search":true},"output":{"max_summary_length":500,"max_search_result_length":300,"format":"plain_text"}}
EOF'

echo "[provision_tier3] Disabling unnecessary services..."
$SSH_CMD "sudo systemctl disable --now snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null; sudo systemctl disable --now amazon-ssm-agent 2>/dev/null; sudo systemctl disable --now ModemManager 2>/dev/null; sudo systemctl disable --now cups-browsed 2>/dev/null; sudo systemctl disable --now avahi-daemon 2>/dev/null; sudo systemctl disable --now apache2 2>/dev/null; sudo systemctl disable --now nginx 2>/dev/null; sudo apt-get remove -y -qq apache2 nginx 2>/dev/null; true"

echo "[provision_tier3] Verifying..."
$SSH_CMD "echo 'UFW:'; sudo ufw status | head -5; echo 'Node:'; node --version; echo 'Web:'; curl -s -o /dev/null -w '%{http_code}' https://www.google.com; echo ''"

echo "[provision_tier3] Provisioning complete."
