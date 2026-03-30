#!/bin/bash
# product-validate.sh — Dispatch Amazon ASIN validation to Tier 3 via RapidAPI Real-Time Amazon Data
# Returns real-time price, delivery, stock status, ratings for specific ASINs
# Usage: product-validate.sh '<asin_list>'
#   asin_list: comma-separated ASINs (e.g., "B0DYTF8L2W,B09V3KXJPB")
set -euo pipefail
ASIN_LIST="${1:?Usage: $0 '<asin_list>'}"
VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
OPS_LOG="/home/ubuntu/dispatch/ops-log.sh"

T_START=$(date +%s%3N)
ASIN_COUNT=$(echo "$ASIN_LIST" | tr ',' '\n' | wc -l)
bash "$OPS_LOG" "Dispatching to Tier 3: product validate ($ASIN_COUNT ASINs)"

T_VAULT=$(date +%s%3N)
RAPIDAPI_KEY=$(bash "$VAULT" get rapidapi api_key)
T_VAULT_DONE=$(date +%s%3N)

T_SSH=$(date +%s%3N)
RESULT=$(ssh tier3 "RAPIDAPI_KEY='$RAPIDAPI_KEY' ASIN_LIST='$ASIN_LIST' NODE_PATH=/usr/lib/node_modules node /home/ubuntu/scripts/product_validate.js" 2>&1) || true
T_SSH_DONE=$(date +%s%3N)

LINES=$(echo "$RESULT" | wc -l)
bash "$OPS_LOG" "Tier 3 product validate: vault=$((T_VAULT_DONE-T_VAULT))ms ssh+rapidapi=$((T_SSH_DONE-T_SSH))ms total=$((T_SSH_DONE-T_START))ms ($ASIN_COUNT ASINs, ${#RESULT} chars)"

# Strip [rapidapi-usage] lines from output (log them separately)
echo "$RESULT" | grep -v '^\[rapidapi-usage\]'
