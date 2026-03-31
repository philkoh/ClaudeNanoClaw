#!/bin/bash
# cache-keepwarm.sh — Send a minimal API request to keep the prompt cache alive
# Runs via systemd timer every 55 minutes. Uses the credential proxy on port 3001.
# Does NOT go through NanoClaw containers — this is a direct API call to warm the cache.
set -euo pipefail

USAGE_DIR="/home/ubuntu/NanoClaw/data/usage"
META_FILE="$USAGE_DIR/last_request_meta.json"
LOG_FILE="$USAGE_DIR/keepwarm.log"

# Check if we have metadata from a recent real request
if [ ! -f "$META_FILE" ]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) SKIP: no last_request_meta.json yet (no real requests made)" >> "$LOG_FILE"
  exit 0
fi

# Check if last real request was within the last 65 minutes
# If so, cache is already warm from real usage — skip
LAST_TS=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$META_FILE','utf8')).ts)" 2>/dev/null || echo "")
if [ -n "$LAST_TS" ]; then
  LAST_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s)
  AGE_MIN=$(( (NOW_EPOCH - LAST_EPOCH) / 60 ))
  if [ "$AGE_MIN" -lt 50 ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) SKIP: last real request was ${AGE_MIN}m ago (cache still warm)" >> "$LOG_FILE"
    exit 0
  fi
fi

# Send a minimal request through the credential proxy
# The proxy will inject the API key and 1-hour TTL
# We use the same model as real requests to hit the same cache
MODEL=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$META_FILE','utf8')).model || 'claude-sonnet-4-6')" 2>/dev/null || echo "claude-sonnet-4-6")

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://127.0.0.1:3001/v1/messages \
  -H "content-type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -H "x-api-key: placeholder" \
  -d "{
    \"model\": \"$MODEL\",
    \"max_tokens\": 1,
    \"system\": \"Respond with OK.\",
    \"messages\": [{\"role\": \"user\", \"content\": \"ping\"}]
  }" 2>&1) || true

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "200" ]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) OK: keep-warm ping succeeded (HTTP $HTTP_CODE)" >> "$LOG_FILE"
else
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) WARN: keep-warm ping returned HTTP $HTTP_CODE" >> "$LOG_FILE"
fi

# Trim log to last 500 lines
tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
