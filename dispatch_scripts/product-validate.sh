#!/bin/bash
# product-validate.sh — Dispatch Amazon ASIN validation to Tier 3 via Pangolinfo
# Returns real-time price, delivery date, stock status, seller for specific ASINs
# Usage: product-validate.sh '<asin_list>' [zip_code]
#   asin_list: comma-separated ASINs (e.g., "B0DYTF8L2W,B09V3KXJPB")
#   zip_code: optional US zip for localized delivery estimates
set -euo pipefail
ASIN_LIST="${1:?Usage: $0 '<asin_list>' [zip_code]}"
ZIP_CODE="${2:-}"
VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
OPS_LOG="/home/ubuntu/dispatch/ops-log.sh"

T_START=$(date +%s%3N)
ASIN_COUNT=$(echo "$ASIN_LIST" | tr ',' '\n' | wc -l)
bash "$OPS_LOG" "Dispatching to Tier 3: product validate ($ASIN_COUNT ASINs)"

T_VAULT=$(date +%s%3N)
PANGOLINFO_KEY=$(bash "$VAULT" get pangolinfo-api key)
T_VAULT_DONE=$(date +%s%3N)

T_SSH=$(date +%s%3N)
RESULT=$(ssh tier3 "PANGOLINFO_API_KEY='$PANGOLINFO_KEY' ASIN_LIST='$ASIN_LIST' ZIP_CODE='$ZIP_CODE' NODE_PATH=/usr/lib/node_modules node /home/ubuntu/scripts/product_validate.js" 2>&1) || true
T_SSH_DONE=$(date +%s%3N)

LINES=$(echo "$RESULT" | wc -l)
bash "$OPS_LOG" "Tier 3 product validate: vault=$((T_VAULT_DONE-T_VAULT))ms ssh+pangolinfo=$((T_SSH_DONE-T_SSH))ms total=$((T_SSH_DONE-T_START))ms ($ASIN_COUNT ASINs, ${#RESULT} chars)"

# Strip [pangolinfo-usage] lines from output (log them separately)
echo "$RESULT" | grep -v '^\[pangolinfo-usage\]'
