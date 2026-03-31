#!/bin/bash
# weekly-cache-trend.sh — Append weekly cache/cost trend line to trend log
# Run via weekly cron. Tracks context growth, cache efficiency, and cost over time.
set -euo pipefail

USAGE_DIR="/home/ubuntu/NanoClaw/data/usage"
ANTHROPIC_FILE="$USAGE_DIR/anthropic_proxy.jsonl"
TREND_FILE="$USAGE_DIR/weekly_trends.log"

WEEK=$(date -u +%Y-%m-%d)

if [ ! -f "$ANTHROPIC_FILE" ]; then
  echo "$WEEK  no_data" >> "$TREND_FILE"
  exit 0
fi

# Analyze last 7 days
node -e "
const fs = require('fs');
const lines = fs.readFileSync('$ANTHROPIC_FILE','utf8').trim().split('\n').filter(Boolean);
const sevenDaysAgo = Date.now() - 7 * 86400000;

let total = 0, cacheHits = 0, cacheMisses = 0;
let totalInput = 0, totalOutput = 0, totalCacheRead = 0, totalCacheCreate = 0;
let maxContext = 0;

for (const line of lines) {
  try {
    const r = JSON.parse(line);
    if (new Date(r.ts).getTime() < sevenDaysAgo) continue;
    total++;
    const ctx = (r.cache_read_input_tokens || 0) + (r.cache_creation_input_tokens || 0) + (r.input_tokens || 0);
    if (ctx > maxContext) maxContext = ctx;
    if (r.cache_read_input_tokens > 0) cacheHits++;
    if (r.cache_creation_input_tokens > 1000) cacheMisses++;
    totalInput += r.input_tokens || 0;
    totalOutput += r.output_tokens || 0;
    totalCacheRead += r.cache_read_input_tokens || 0;
    totalCacheCreate += r.cache_creation_input_tokens || 0;
  } catch {}
}

const hitRate = total > 0 ? Math.round((cacheHits / total) * 100) : 0;
const avgContext = total > 0 ? Math.round((totalCacheRead + totalCacheCreate) / total) : 0;

// Cost estimate (Sonnet 4.6 rates)
const cost = (totalInput * 3.0 + totalOutput * 15.0 + totalCacheRead * 0.30 + totalCacheCreate * 6.0) / 1e6;

const line = '$WEEK' +
  '  reqs=' + total +
  '  avg_ctx=' + (avgContext / 1000).toFixed(1) + 'K' +
  '  max_ctx=' + (maxContext / 1000).toFixed(1) + 'K' +
  '  hit_rate=' + hitRate + '%' +
  '  cold_starts=' + cacheMisses +
  '  cost=\$' + cost.toFixed(2);

console.log(line);
fs.appendFileSync('$TREND_FILE', line + '\n');
"

echo "Trend line appended to $TREND_FILE"
