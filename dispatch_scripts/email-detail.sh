#!/bin/bash
# email-detail.sh — Dispatch email detail lookup to Tier 3
# Usage: email-detail.sh <search_query> [max_results]
#        email-detail.sh --interpret <base64_prompt> <search_query> [max_results]
# Without --interpret: returns raw email bodies (fast, no Gemini)
# With --interpret: sends email body + images to Gemini with the prompt
# The interpret prompt must be base64-encoded (avoids shell quoting issues through SSH gateway)
set -euo pipefail

INTERPRET=""
if [ "${1:-}" = "--interpret" ]; then
  INTERPRET_B64="${2:-}"
  shift 2
  if [ -z "$INTERPRET_B64" ]; then
    echo "ERROR: --interpret requires a base64-encoded prompt"
    exit 1
  fi
  INTERPRET=$(echo "$INTERPRET_B64" | base64 -d)
fi

QUERY="${1:-}"
MAX_RESULTS="${2:-3}"
VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
OPS_LOG="/home/ubuntu/dispatch/ops-log.sh"

if [ -z "$QUERY" ]; then
  echo "ERROR: search query required. Usage: email-detail.sh [--interpret <base64_prompt>] <query> [max_results]"
  exit 1
fi

T_START=$(date +%s%3N)
MODE="raw"
[ -n "$INTERPRET" ] && MODE="interpret"
bash "$OPS_LOG" "Dispatching to Tier 3: email detail lookup '$QUERY' (max $MAX_RESULTS, mode=$MODE)"

T_VAULT=$(date +%s%3N)
IMAP_USER=$(bash "$VAULT" get gmail-imap user)
IMAP_PASS=$(bash "$VAULT" get gmail-imap password)
GEMINI_KEY=""
if [ -n "$INTERPRET" ]; then
  GEMINI_KEY=$(bash "$VAULT" get gemini-api key)
fi
T_VAULT_DONE=$(date +%s%3N)

T_SSH=$(date +%s%3N)
RESULT=$(ssh tier3 "GMAIL_IMAP_USER='$IMAP_USER' GMAIL_IMAP_APP_PASSWORD='$IMAP_PASS' GEMINI_API_KEY='$GEMINI_KEY' EMAIL_QUERY='$QUERY' EMAIL_MAX_RESULTS=$MAX_RESULTS EMAIL_INTERPRET='$INTERPRET' NODE_PATH=/usr/lib/node_modules node /home/ubuntu/scripts/email_detail.js" 2>&1) || true
T_SSH_DONE=$(date +%s%3N)

LINES=$(echo "$RESULT" | wc -l)
bash "$OPS_LOG" "Tier 3 email detail: vault=$((T_VAULT_DONE-T_VAULT))ms ssh+imap=$((T_SSH_DONE-T_SSH))ms total=$((T_SSH_DONE-T_START))ms mode=$MODE ($LINES lines, ${#RESULT} chars)"

echo "$RESULT"
