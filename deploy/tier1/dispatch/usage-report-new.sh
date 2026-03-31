#!/bin/bash
# usage-report.sh — Read API usage data for Anthropic and Gemini with cost estimates
# Usage: usage-report.sh [days]
set -euo pipefail

DAYS="${1:-1}"
VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
USAGE_DIR="/home/ubuntu/NanoClaw/data/usage"
COST_SCRIPT="/home/ubuntu/scripts/usage-cost.js"

mkdir -p "$USAGE_DIR"

END_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_DATE=$(date -u -d "$DAYS days ago" +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -v-${DAYS}d +%Y-%m-%dT00:00:00Z)

echo "=== API Usage & Cost Report ==="
echo "Period: last $DAYS day(s) (since $START_DATE)"
echo ""

# Main cost report (Anthropic + Gemini)
node "$COST_SCRIPT" "$USAGE_DIR/anthropic_proxy.jsonl" "$USAGE_DIR/gemini_dispatch.jsonl" "$START_DATE"

echo ""

# --- Anthropic: Usage API cross-check (if admin key available) ---
echo "--- Anthropic (Usage API Cross-Check) ---"
ADMIN_KEY=$(bash "$VAULT" get anthropic-admin key 2>/dev/null || echo "")
if [ -n "$ADMIN_KEY" ]; then
  API_RESULT=$(curl -s "https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=${START_DATE}&ending_at=${END_DATE}&group_by[]=model&bucket_width=1d" \
    -H "anthropic-version: 2023-06-01" \
    -H "x-api-key: $ADMIN_KEY" 2>&1) || true

  echo "$API_RESULT" | node -e "
    let buf=''; process.stdin.on('data',c=>buf+=c); process.stdin.on('end',()=>{
      try {
        const data = JSON.parse(buf);
        if (data.error) { console.log('API error: ' + JSON.stringify(data.error)); return; }
        if (!data.data) { console.log('Unexpected response'); return; }
        let ti=0, to=0, tcr=0;
        for (const b of data.data) {
          ti += b.input_tokens||0; to += b.output_tokens||0; tcr += b.cache_read_input_tokens||0;
          console.log('  ' + (b.bucket_start_time||'').slice(0,10) + ' ' + (b.model||'all') + ': ' + (b.input_tokens||0).toLocaleString() + ' in, ' + (b.output_tokens||0).toLocaleString() + ' out, ' + (b.cache_read_input_tokens||0).toLocaleString() + ' cached');
        }
        console.log('Totals: ' + ti.toLocaleString() + ' in, ' + to.toLocaleString() + ' out, ' + tcr.toLocaleString() + ' cached');
      } catch(e) { console.log('Parse error: ' + e.message); }
    });
  " 2>/dev/null || echo "Failed to parse Usage API response"
else
  echo "(no admin key — add as 'anthropic-admin' field 'key' to enable cross-check)"
fi

echo ""
echo "=== End Report ==="
