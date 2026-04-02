#!/bin/bash
# create-draft.sh — Create an Exchange draft in phil@emtera.com's mailbox
# Runs locally on Tier 1 (no dispatch to Tier 3) via Microsoft Graph API.
# Usage: create-draft.sh <base64_json>
#   JSON payload: {"to":"addr","subject":"subj","body":"html_body","cc":"addr","importance":"normal"}
#   Required: to, subject, body. Optional: cc, importance (default: normal).
set -euo pipefail

PAYLOAD_B64="${1:-}"
if [ -z "$PAYLOAD_B64" ]; then
  echo "ERROR: base64-encoded JSON payload required"
  echo "Usage: create-draft.sh <base64_json>"
  echo 'JSON: {"to":"addr","subject":"subj","body":"body text","cc":"addr","importance":"normal"}'
  exit 1
fi

VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
OPS_LOG="/home/ubuntu/dispatch/ops-log.sh"
T_START=$(date +%s%3N)

# Decode payload
PAYLOAD=$(echo "$PAYLOAD_B64" | base64 -d 2>/dev/null) || {
  echo "ERROR: Invalid base64 payload"
  exit 1
}

# Extract fields with node (safe JSON parsing)
TO=$(echo "$PAYLOAD" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.stdout.write(d.to||'')")
SUBJECT=$(echo "$PAYLOAD" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.stdout.write(d.subject||'')")
BODY=$(echo "$PAYLOAD" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.stdout.write(d.body||'')")
CC=$(echo "$PAYLOAD" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.stdout.write(d.cc||'')")
IMPORTANCE=$(echo "$PAYLOAD" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.stdout.write(d.importance||'normal')")

if [ -z "$TO" ] || [ -z "$SUBJECT" ] || [ -z "$BODY" ]; then
  echo "ERROR: JSON must include 'to', 'subject', and 'body' fields"
  exit 1
fi

bash "$OPS_LOG" "Creating Exchange draft: to=$TO subject=$(echo "$SUBJECT" | head -c 50)"

# Get vault credentials
T_VAULT=$(date +%s%3N)
TENANT_ID=$(bash "$VAULT" get msgraph-drafts tenant_id)
CLIENT_ID=$(bash "$VAULT" get msgraph-drafts client_id)
CLIENT_SECRET=$(bash "$VAULT" get msgraph-drafts client_secret)
USER_EMAIL=$(bash "$VAULT" get msgraph-drafts user_email)
T_VAULT_DONE=$(date +%s%3N)

# Get OAuth token
T_AUTH=$(date +%s%3N)
TOKEN_RESPONSE=$(curl -s -X POST \
  "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$CLIENT_ID&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default&client_secret=$CLIENT_SECRET&grant_type=client_credentials")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | node -e "
  const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
  if (d.error) { console.error('Auth error: ' + d.error + ' — ' + (d.error_description||'')); process.exit(1); }
  process.stdout.write(d.access_token||'');
") || {
  echo "ERROR: Failed to get OAuth token"
  echo "$TOKEN_RESPONSE" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.error(d.error_description||d.error||'Unknown auth error')" 2>&1
  exit 1
}
T_AUTH_DONE=$(date +%s%3N)

if [ -z "$ACCESS_TOKEN" ]; then
  echo "ERROR: Empty access token from OAuth"
  exit 1
fi

# Build the Graph API request body
GRAPH_BODY=$(node -e "
  const to = $(echo "$TO" | node -e "console.log(JSON.stringify(require('fs').readFileSync('/dev/stdin','utf8').trim()))");
  const subject = $(echo "$SUBJECT" | node -e "console.log(JSON.stringify(require('fs').readFileSync('/dev/stdin','utf8')))");
  const body = $(echo "$BODY" | node -e "console.log(JSON.stringify(require('fs').readFileSync('/dev/stdin','utf8')))");
  const cc = $(echo "$CC" | node -e "console.log(JSON.stringify(require('fs').readFileSync('/dev/stdin','utf8').trim()))");
  const importance = $(echo "$IMPORTANCE" | node -e "console.log(JSON.stringify(require('fs').readFileSync('/dev/stdin','utf8').trim()))");

  const msg = {
    subject: subject,
    body: { contentType: 'HTML', content: body },
    toRecipients: to.split(',').filter(Boolean).map(e => ({ emailAddress: { address: e.trim() } })),
    importance: importance
  };
  if (cc) {
    msg.ccRecipients = cc.split(',').filter(Boolean).map(e => ({ emailAddress: { address: e.trim() } }));
  }
  console.log(JSON.stringify(msg));
")

# Create draft via Graph API
T_API=$(date +%s%3N)
API_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "https://graph.microsoft.com/v1.0/users/$USER_EMAIL/messages" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$GRAPH_BODY")

HTTP_CODE=$(echo "$API_RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$API_RESPONSE" | sed '$d')
T_API_DONE=$(date +%s%3N)

if [ "$HTTP_CODE" = "201" ]; then
  DRAFT_ID=$(echo "$RESPONSE_BODY" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.stdout.write(d.id||'')")
  DRAFT_SUBJECT=$(echo "$RESPONSE_BODY" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.stdout.write(d.subject||'')")
  DRAFT_WEB_LINK=$(echo "$RESPONSE_BODY" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); process.stdout.write(d.webLink||'')")

  bash "$OPS_LOG" "Draft created: vault=$((T_VAULT_DONE-T_VAULT))ms auth=$((T_AUTH_DONE-T_AUTH))ms api=$((T_API_DONE-T_API))ms total=$((T_API_DONE-T_START))ms"

  echo "SUCCESS: Draft created in $USER_EMAIL Drafts folder"
  echo "Subject: $DRAFT_SUBJECT"
  echo "To: $TO"
  [ -n "$CC" ] && echo "CC: $CC"
  echo "Draft ID: $DRAFT_ID"
else
  ERROR_MSG=$(echo "$RESPONSE_BODY" | node -e "
    try { const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.error(d.error?.message||JSON.stringify(d.error)||'Unknown'); }
    catch(e) { console.error('Non-JSON response'); }
  " 2>&1)
  bash "$OPS_LOG" "Draft creation FAILED: HTTP $HTTP_CODE — $ERROR_MSG"
  echo "ERROR: Draft creation failed (HTTP $HTTP_CODE)"
  echo "$ERROR_MSG"
  exit 1
fi
