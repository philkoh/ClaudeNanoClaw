#!/bin/bash
# usage-lastcall.sh — Show token details for the most recent API call
# Usage: usage-lastcall.sh [n] (default: last 1 call, or last N calls)
set -euo pipefail
COUNT="${1:-1}"
USAGE_FILE="/home/ubuntu/NanoClaw/data/usage/anthropic_proxy.jsonl"

if [ ! -f "$USAGE_FILE" ]; then
  echo "No usage data yet"
  exit 0
fi

tail -"$COUNT" "$USAGE_FILE" | node -e "
const pricing = {
  'claude-sonnet-4-6': { input: 3.00, output: 15.00, cache_read: 0.30, cache_create_5m: 3.75, cache_create_1h: 6.00 },
  '_default': { input: 3.00, output: 15.00, cache_read: 0.30, cache_create_5m: 3.75, cache_create_1h: 6.00 },
};
let buf = '';
process.stdin.on('data', c => buf += c);
process.stdin.on('end', () => {
  const lines = buf.trim().split('\n').filter(Boolean);
  for (const line of lines) {
    const r = JSON.parse(line);
    const p = pricing[r.model] || pricing['_default'];
    const ccRate = p.cache_create_1h;  // assume 1h TTL is active
    const cost = (r.input_tokens * p.input + r.output_tokens * p.output +
      r.cache_read_input_tokens * p.cache_read + r.cache_creation_input_tokens * ccRate) / 1e6;
    const cacheHit = r.cache_read_input_tokens > 0 ? 'yes' : 'no (cold start)';
    console.log('Time: ' + r.ts);
    console.log('Model: ' + r.model);
    console.log('Input: ' + r.input_tokens + ' tokens');
    console.log('Output: ' + r.output_tokens + ' tokens');
    console.log('Cache read: ' + r.cache_read_input_tokens.toLocaleString() + ' tokens (hit: ' + cacheHit + ')');
    console.log('Cache creation: ' + r.cache_creation_input_tokens.toLocaleString() + ' tokens');
    console.log('TTFB: ' + r.ttfb_ms + 'ms');
    console.log('Total elapsed: ' + r.elapsed_ms + 'ms');
    console.log('Estimated cost: \$' + cost.toFixed(4));
    if (lines.length > 1) console.log('---');
  }
});
"
