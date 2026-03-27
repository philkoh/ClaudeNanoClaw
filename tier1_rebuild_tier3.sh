#!/bin/bash
# rebuild_tier3.sh — Run ON Tier 1 to destroy and recreate Tier 3
# Per plan Section 12: nightly rebuild of Tier 3 (fully-exposed VM)
set -eu

INSTANCE_NAME="OpenClaw-Tier3"
STATIC_IP_NAME="OpenClaw-Tier3-IP"
TIER1_IP="174.129.11.27"
BLUEPRINT="ubuntu_24_04"
BUNDLE="medium_3_0"
AZ="us-east-1a"
KEY_PAIR="NanoClaw-Tier1-Key"
TIER3_KEY="$HOME/.ssh/tier3_key"
TIER3_PUBKEY="$(cat $HOME/.ssh/tier3_key.pub)"

LOG="/home/ubuntu/logs/rebuild_tier3_$(date +%Y%m%d_%H%M%S).log"
mkdir -p /home/ubuntu/logs

exec > >(tee -a "$LOG") 2>&1

echo "[rebuild_tier3] $(date -u) — Starting Tier 3 rebuild"

# 1. Detach static IP (if attached)
echo "[rebuild_tier3] Detaching static IP..."
aws lightsail detach-static-ip --static-ip-name "$STATIC_IP_NAME" 2>/dev/null || true
sleep 5

# 2. Delete current instance
echo "[rebuild_tier3] Deleting instance $INSTANCE_NAME..."
aws lightsail delete-instance --instance-name "$INSTANCE_NAME" 2>/dev/null || true
sleep 30

# 3. Create fresh instance
echo "[rebuild_tier3] Creating fresh instance..."
aws lightsail create-instances \
    --instance-names "$INSTANCE_NAME" \
    --blueprint-id "$BLUEPRINT" \
    --bundle-id "$BUNDLE" \
    --availability-zone "$AZ" \
    --key-pair-name "$KEY_PAIR"

# 4. Wait for running state
echo "[rebuild_tier3] Waiting for instance to be running..."
for i in $(seq 1 40); do
    STATE=$(aws lightsail get-instance --instance-name "$INSTANCE_NAME" \
        --query 'instance.state.name' --output text 2>/dev/null || echo "pending")
    if [ "$STATE" = "running" ]; then
        echo "[rebuild_tier3] Instance running after $((i * 10)) seconds."
        break
    fi
    sleep 10
done

# 5. Attach static IP
echo "[rebuild_tier3] Attaching static IP..."
aws lightsail attach-static-ip \
    --static-ip-name "$STATIC_IP_NAME" \
    --instance-name "$INSTANCE_NAME"

# 6. Lock down Lightsail firewall to Tier 1 SSH only
echo "[rebuild_tier3] Restricting Lightsail firewall..."
aws lightsail put-instance-public-ports \
    --instance-name "$INSTANCE_NAME" \
    --port-infos "[{\"fromPort\":22,\"toPort\":22,\"protocol\":\"tcp\",\"cidrs\":[\"${TIER1_IP}/32\"]}]"

# 7. Get the static IP (should be same as before)
TIER3_IP=$(aws lightsail get-static-ip --static-ip-name "$STATIC_IP_NAME" \
    --query 'staticIp.ipAddress' --output text)
echo "[rebuild_tier3] Tier 3 IP: $TIER3_IP"

# 8. Wait for SSH and add our key
echo "[rebuild_tier3] Waiting for SSH availability..."
ssh-keygen -R "$TIER3_IP" 2>/dev/null || true

# We need to use the Lightsail key initially to add our ed25519 key
# The Lightsail key should be in a secure location on Tier 1
LIGHTSAIL_KEY="/home/ubuntu/.ssh/lightsail_bootstrap_key.pem"
if [ ! -f "$LIGHTSAIL_KEY" ]; then
    echo "[rebuild_tier3] ERROR: Bootstrap key not found at $LIGHTSAIL_KEY"
    echo "[rebuild_tier3] Cannot add Tier 1 SSH key to new instance."
    echo "[rebuild_tier3] Manual intervention required."
    exit 1
fi

for i in $(seq 1 30); do
    if ssh -i "$LIGHTSAIL_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        ubuntu@"$TIER3_IP" "echo ok" > /dev/null 2>&1; then
        echo "[rebuild_tier3] SSH available."
        break
    fi
    sleep 10
done

# Add our ed25519 key
ssh -i "$LIGHTSAIL_KEY" -o StrictHostKeyChecking=no ubuntu@"$TIER3_IP" \
    "echo '$TIER3_PUBKEY' >> ~/.ssh/authorized_keys"
echo "[rebuild_tier3] Tier 1 SSH key added."

# Verify ed25519 key works
ssh -i "$TIER3_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    ubuntu@"$TIER3_IP" "echo ed25519_ok" > /dev/null 2>&1
echo "[rebuild_tier3] Ed25519 key verified."

# 9. Run provisioning
echo "[rebuild_tier3] Running provisioning script..."
bash /home/ubuntu/scripts/provision_tier3.sh

# 10. Remove the Lightsail key from authorized_keys on Tier 3 (only keep ed25519)
# This is optional but improves security
ssh -i "$TIER3_KEY" ubuntu@"$TIER3_IP" \
    "grep -v 'NanoClaw-Tier1-Key' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>/dev/null || true

echo "[rebuild_tier3] $(date -u) — Tier 3 rebuild complete."
echo "[rebuild_tier3] Log saved to: $LOG"
