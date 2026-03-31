#!/bin/bash
# memory-search.sh — Hybrid semantic+keyword search over PhilClaw memory
# Usage: memory-search.sh "<query>" [limit]
set -euo pipefail
QUERY="${1:?Usage: $0 \"<query>\" [limit]}"
LIMIT="${2:-10}"
VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
OPS_LOG="/home/ubuntu/dispatch/ops-log.sh"
DB_PATH="/home/ubuntu/NanoClaw/data/memory-index.db"
SEARCH_SCRIPT="/home/ubuntu/scripts/memory-search.js"

T_START=$(date +%s%3N)

T_VAULT=$(date +%s%3N)
GEMINI_KEY=$(bash "$VAULT" get gemini-api key)
T_VAULT_DONE=$(date +%s%3N)

T_SEARCH=$(date +%s%3N)
RESULT=$(GEMINI_API_KEY="$GEMINI_KEY" NODE_PATH=/home/ubuntu/NanoClaw/node_modules node "$SEARCH_SCRIPT" "$DB_PATH" "$QUERY" "$LIMIT" 2>&1) || true
T_SEARCH_DONE=$(date +%s%3N)

LINES=$(echo "$RESULT" | wc -l)
bash "$OPS_LOG" "Memory search: vault=$((T_VAULT_DONE-T_VAULT))ms search=$((T_SEARCH_DONE-T_SEARCH))ms total=$((T_SEARCH_DONE-T_START))ms query='${QUERY:0:80}' ($LINES lines, ${#RESULT} chars)"

echo "$RESULT"
