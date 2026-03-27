#!/bin/bash
# hard_rebuild_tier3.sh — Run from a machine with AWS Lightsail API access
# Destroys and recreates the Tier 3 instance from scratch
# This is the full rebuild per plan Section 12.
set -eu

INSTANCE_NAME="OpenClaw-Tier3"
STATIC_IP_NAME="OpenClaw-Tier3-IP"
TIER1_IP="174.129.11.27"
BLUEPRINT="ubuntu_24_04"
BUNDLE="medium_3_0"
AZ="us-east-1a"
KEY_PAIR="NanoClaw-Tier1-Key"
TIER1_KEY="/home/phil/ClaudeNanoClawCreator/NanoClaw-Tier1-Key.pem"
USERDATA="/home/phil/ClaudeNanoClawCreator/tier3_userdata.sh"

echo "[hard_rebuild] $(date -u) — Starting Tier 3 hard rebuild"

# 1. Detach static IP
echo "[hard_rebuild] Detaching static IP..."
aws lightsail detach-static-ip --static-ip-name "$STATIC_IP_NAME" 2>/dev/null || true
sleep 5

# 2. Delete current instance
echo "[hard_rebuild] Deleting instance..."
aws lightsail delete-instance --instance-name "$INSTANCE_NAME" 2>/dev/null || true
sleep 30

# 3. Create fresh instance with user-data
echo "[hard_rebuild] Creating fresh instance..."
aws lightsail create-instances \
    --instance-names "$INSTANCE_NAME" \
    --blueprint-id "$BLUEPRINT" \
    --bundle-id "$BUNDLE" \
    --availability-zone "$AZ" \
    --key-pair-name "$KEY_PAIR" \
    --user-data "file://$USERDATA"

# 4. Wait for running state
echo "[hard_rebuild] Waiting for instance..."
for i in $(seq 1 40); do
    STATE=$(aws lightsail get-instance --instance-name "$INSTANCE_NAME" \
        --query 'instance.state.name' --output text 2>/dev/null || echo "pending")
    if [ "$STATE" = "running" ]; then
        echo "[hard_rebuild] Instance running after $((i * 10)) seconds."
        break
    fi
    sleep 10
done

# 5. Attach static IP
echo "[hard_rebuild] Attaching static IP..."
aws lightsail attach-static-ip \
    --static-ip-name "$STATIC_IP_NAME" \
    --instance-name "$INSTANCE_NAME"

# 6. Lock down Lightsail firewall
echo "[hard_rebuild] Restricting Lightsail firewall..."
aws lightsail put-instance-public-ports \
    --instance-name "$INSTANCE_NAME" \
    --port-infos "[{\"fromPort\":22,\"toPort\":22,\"protocol\":\"tcp\",\"cidrs\":[\"${TIER1_IP}/32\"]}]"

TIER3_IP=$(aws lightsail get-static-ip --static-ip-name "$STATIC_IP_NAME" \
    --query 'staticIp.ipAddress' --output text)
echo "[hard_rebuild] Tier 3 IP: $TIER3_IP"

# 7. Wait for cloud-init and user-data to complete
echo "[hard_rebuild] Waiting 120s for cloud-init to complete..."
sleep 120

# 8. Verify from Tier 1
echo "[hard_rebuild] Verifying Tier 1 -> Tier 3 SSH..."
ssh -i "$TIER1_KEY" ubuntu@"$TIER1_IP" "ssh tier3 'echo TIER3_SSH_OK'"

echo "[hard_rebuild] $(date -u) — Tier 3 hard rebuild complete."
echo "[hard_rebuild] Static IP: $TIER3_IP"
