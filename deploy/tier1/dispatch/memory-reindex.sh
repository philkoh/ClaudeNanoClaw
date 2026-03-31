#!/bin/bash
# memory-reindex.sh — Re-index memory files for semantic search
# Usage: memory-reindex.sh [group-folder]
set -euo pipefail
GROUP="${1:-telegram_main}"
VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
OPS_LOG="/home/ubuntu/dispatch/ops-log.sh"
MEMORY_DIR="/home/ubuntu/NanoClaw/groups/$GROUP"
DB_PATH="/home/ubuntu/NanoClaw/data/memory-index.db"
INDEX_SCRIPT="/home/ubuntu/scripts/memory-index.js"

T_START=$(date +%s%3N)
bash "$OPS_LOG" "Memory re-index starting for group=$GROUP"

GEMINI_KEY=$(bash "$VAULT" get gemini-api key)

RESULT=$(GEMINI_API_KEY="$GEMINI_KEY" NODE_PATH=/home/ubuntu/NanoClaw/node_modules node "$INDEX_SCRIPT" "$MEMORY_DIR" "$DB_PATH" 2>&1) || true

T_DONE=$(date +%s%3N)
bash "$OPS_LOG" "Memory re-index: group=$GROUP time=$((T_DONE-T_START))ms"

echo "$RESULT"
