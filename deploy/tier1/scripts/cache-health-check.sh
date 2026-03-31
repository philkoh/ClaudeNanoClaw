#!/bin/bash
# cache-health-check.sh — Check cache health from proxy logs (for heartbeat integration)
# Outputs: JSON with cache stats. Non-zero exit if anomalies detected.
set -euo pipefail

USAGE_DIR="/home/ubuntu/NanoClaw/data/usage"
ANTHROPIC_FILE="$USAGE_DIR/anthropic_proxy.jsonl"

if [ ! -f "$ANTHROPIC_FILE" ]; then
  echo '{"status":"no_data","message":"No proxy usage data yet"}'
  exit 0
fi

# Analyze last hour of requests
node -e "
const fs = require('fs');
const lines = fs.readFileSync('$ANTHROPIC_FILE','utf8').trim().split('\n').filter(Boolean);
const oneHourAgo = Date.now() - 3600000;
let total = 0, cacheHits = 0, cacheMisses = 0, totalCacheRead = 0, totalCacheCreate = 0;
let lastTs = null;

for (const line of lines) {
  try {
    const r = JSON.parse(line);
    if (new Date(r.ts).getTime() < oneHourAgo) continue;
    total++;
    lastTs = r.ts;
    if (r.cache_read_input_tokens > 0) {
      cacheHits++;
      totalCacheRead += r.cache_read_input_tokens;
    }
    if (r.cache_creation_input_tokens > 1000) {
      cacheMisses++;
      totalCacheCreate += r.cache_creation_input_tokens;
    }
  } catch {}
}

const hitRate = total > 0 ? Math.round((cacheHits / total) * 100) : -1;
const avgContext = total > 0 ? Math.round((totalCacheRead + totalCacheCreate) / total) : 0;
const issues = [];

if (total > 2 && hitRate < 50) issues.push('Low cache hit rate: ' + hitRate + '%');
if (avgContext > 80000) issues.push('Context size growing: ' + avgContext.toLocaleString() + ' tokens avg');
if (cacheMisses > 5) issues.push('Frequent cold starts: ' + cacheMisses + ' in last hour');

// Check keep-warm health
const keepwarmLog = '$USAGE_DIR/keepwarm.log';
let keepwarmStatus = 'unknown';
if (fs.existsSync(keepwarmLog)) {
  const kwLines = fs.readFileSync(keepwarmLog, 'utf8').trim().split('\n');
  const lastLine = kwLines[kwLines.length - 1] || '';
  if (lastLine.includes('OK:')) keepwarmStatus = 'healthy';
  else if (lastLine.includes('SKIP:')) keepwarmStatus = 'idle';
  else if (lastLine.includes('WARN:')) { keepwarmStatus = 'failing'; issues.push('Keep-warm ping failing'); }
} else {
  keepwarmStatus = 'not_running';
}

const result = {
  status: issues.length > 0 ? 'warning' : 'healthy',
  requests_1h: total,
  cache_hit_rate: hitRate + '%',
  cold_starts_1h: cacheMisses,
  avg_context_tokens: avgContext,
  keepwarm: keepwarmStatus,
  last_request: lastTs,
  issues: issues.length > 0 ? issues : undefined,
};

console.log(JSON.stringify(result));
process.exit(issues.length > 0 ? 1 : 0);
" || true
