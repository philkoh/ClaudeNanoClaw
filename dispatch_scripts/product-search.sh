#!/bin/bash
# product-search.sh — Dispatch Amazon product discovery to Tier 3
# Uses Gemini grounded search with site:amazon.com to find products and extract ASINs
# Usage: product-search.sh '<query>'
set -euo pipefail
QUERY="${1:?Usage: $0 '<search query>'}"
VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
OPS_LOG="/home/ubuntu/dispatch/ops-log.sh"

T_START=$(date +%s%3N)
bash "$OPS_LOG" "Dispatching to Tier 3: product search ($QUERY)"

T_VAULT=$(date +%s%3N)
GEMINI_KEY=$(bash "$VAULT" get gemini-api key)
T_VAULT_DONE=$(date +%s%3N)

T_SSH=$(date +%s%3N)
RESULT=$(ssh tier3 "GEMINI_API_KEY='$GEMINI_KEY' SEARCH_QUERY='$QUERY' NODE_PATH=/usr/lib/node_modules node /home/ubuntu/scripts/product_search.js" 2>&1) || true
T_SSH_DONE=$(date +%s%3N)

LINES=$(echo "$RESULT" | wc -l)
bash "$OPS_LOG" "Tier 3 product search: vault=$((T_VAULT_DONE-T_VAULT))ms ssh+gemini=$((T_SSH_DONE-T_SSH))ms total=$((T_SSH_DONE-T_START))ms ($LINES lines, ${#RESULT} chars)"

echo "$RESULT" | bash "$(dirname "$0")/log-gemini-usage.sh" product-search
