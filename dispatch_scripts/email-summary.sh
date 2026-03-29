#!/bin/bash
# email-summary.sh — Dispatch email summarization to Tier 3
# Usage: email-summary.sh [count]
set -euo pipefail
COUNT="${1:-10}"
VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
OPS_LOG="/home/ubuntu/dispatch/ops-log.sh"

T_START=$(date +%s%3N)
bash "$OPS_LOG" "Dispatching to Tier 3: email triage ($COUNT emails)"

T_VAULT=$(date +%s%3N)
IMAP_USER=$(bash "$VAULT" get gmail-imap user)
IMAP_PASS=$(bash "$VAULT" get gmail-imap password)
GEMINI_KEY=$(bash "$VAULT" get gemini-api key)
T_VAULT_DONE=$(date +%s%3N)

T_SSH=$(date +%s%3N)
RESULT=$(ssh tier3 "GMAIL_IMAP_USER='$IMAP_USER' GMAIL_IMAP_APP_PASSWORD='$IMAP_PASS' GEMINI_API_KEY='$GEMINI_KEY' NODE_PATH=/usr/lib/node_modules EMAIL_COUNT=$COUNT node /home/ubuntu/scripts/email_summarize.js" 2>&1) || true
T_SSH_DONE=$(date +%s%3N)

LINES=$(echo "$RESULT" | wc -l)
bash "$OPS_LOG" "Tier 3 email triage: vault=$((T_VAULT_DONE-T_VAULT))ms ssh+gemini=$((T_SSH_DONE-T_SSH))ms total=$((T_SSH_DONE-T_START))ms ($LINES lines, ${#RESULT} chars)"

echo "$RESULT" | bash "$(dirname "$0")/log-gemini-usage.sh" email-summary
