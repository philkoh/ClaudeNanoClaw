#!/bin/bash
# ops-log.sh — Log dispatch activity to file (always) and Telegram ops channel (if configured)
# Usage: ops-log.sh "<message>"
set -euo pipefail
MSG="${1:?Usage: $0 \"<message>\"}"

LOG_DIR="/home/ubuntu/logs/ops"
LOG_FILE="$LOG_DIR/dispatch.log"

# Always log to file
mkdir -p "$LOG_DIR"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $MSG" >> "$LOG_FILE"

# Rotate: keep last 10000 lines
if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 10000 ]; then
  tail -5000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

# Send to Telegram ops channel if configured
OPS_CHAT_ID="${TELEGRAM_OPS_CHAT_ID:-}"
if [ -z "$OPS_CHAT_ID" ]; then
  # Try reading from config file
  OPS_CHAT_ID=$(grep TELEGRAM_OPS_CHAT_ID /home/ubuntu/NanoClaw/.env 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
fi

if [ -n "$OPS_CHAT_ID" ]; then
  BOT_TOKEN=$(grep TELEGRAM_BOT_TOKEN /home/ubuntu/NanoClaw/.env 2>/dev/null | cut -d= -f2- | tr -d '"')
  if [ -n "$BOT_TOKEN" ]; then
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d chat_id="$OPS_CHAT_ID" \
      -d text="$MSG" \
      -d parse_mode=Markdown \
      > /dev/null 2>&1 || true
  fi
fi
