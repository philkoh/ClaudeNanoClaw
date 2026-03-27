#!/bin/bash
# dispatch_portal.sh — Tier 1 orchestrator for portal sessions on Tier 2
# Handles the full cycle: open firewall → inject creds → run session → close
# Usage: dispatch_portal.sh <portal_name> <task_instructions>
# Portal credentials are read from the Tier 1 vault.
set -euo pipefail

PORTAL_NAME="${1:?Usage: $0 <portal_name> <task_instructions>}"
TASK="${2:?Usage: $0 <portal_name> <task_instructions>}"

VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
TIER2="ssh tier2"

echo "[dispatch] Starting portal session: $PORTAL_NAME"
echo "[dispatch] Task: $TASK"

# 1. Read portal config from vault
PORTAL_URL=$(bash "$VAULT" get "$PORTAL_NAME" url)
PORTAL_DOMAINS=$(bash "$VAULT" get "$PORTAL_NAME" domains 2>/dev/null || echo "$PORTAL_URL" | sed 's|https\?://||;s|/.*||')
PORTAL_USER=$(bash "$VAULT" get "$PORTAL_NAME" username)
PORTAL_PASS=$(bash "$VAULT" get "$PORTAL_NAME" password)
ANTHROPIC_KEY=$(bash "$VAULT" get "anthropic-api" key)

echo "[dispatch] Portal URL: $PORTAL_URL"
echo "[dispatch] Allowed domains: $PORTAL_DOMAINS"

# 2. Open the portal firewall on Tier 2
echo "[dispatch] Opening portal firewall..."
$TIER2 "bash /home/ubuntu/scripts/open_portal.sh $PORTAL_DOMAINS"

# 3. Run the OpenClaw session with injected credentials
echo "[dispatch] Launching OpenClaw session..."
AGENT_MSG="You are a portal automation agent. Navigate to $PORTAL_URL, log in with credentials from env vars PORTAL_USER and PORTAL_PASS, then: $TASK. Return structured results as JSON. Do NOT navigate anywhere outside $PORTAL_URL subpages. Clear cookies when done."

RESULT=$($TIER2 "
  docker run --rm \
    --label openclaw-session \
    --network bridge \
    -e HTTPS_PROXY=http://172.17.0.1:3128 \
    -e HTTP_PROXY=http://172.17.0.1:3128 \
    -e PORTAL_USER='$PORTAL_USER' \
    -e PORTAL_PASS='$PORTAL_PASS' \
    -e ANTHROPIC_API_KEY='$ANTHROPIC_KEY' \
    -e OPENCLAW_HEADLESS=true \
    ghcr.io/openclaw/openclaw:latest \
    openclaw agent --local \
      --session-id portal-\$(date +%s) \
      --message '$AGENT_MSG' \
      --json \
      --timeout 300 \
    2>&1
") || true

echo "[dispatch] Session output:"
echo "$RESULT"

# 4. Close the portal firewall
echo "[dispatch] Closing portal firewall..."
$TIER2 "bash /home/ubuntu/scripts/close_portal.sh"

echo "[dispatch] Portal session complete: $PORTAL_NAME"
