#!/bin/bash
# usage-report.sh — Read API usage data for Anthropic and Gemini
# Usage: usage-report.sh [days]
# Returns a summary of token usage from both proxy tracking and dispatch logs.
# If an Anthropic admin key is in the vault, also queries the Usage API for cross-check.
set -euo pipefail

DAYS="${1:-1}"
VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
USAGE_DIR="/home/ubuntu/NanoClaw/data/usage"

mkdir -p "$USAGE_DIR"

# Calculate the date range
END_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_DATE=$(date -u -d "$DAYS days ago" +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -v-${DAYS}d +%Y-%m-%dT00:00:00Z)
TODAY=$(date -u +%Y-%m-%d)

echo "=== API Usage Report ==="
echo "Period: last $DAYS day(s) (since $START_DATE)"
echo ""

# --- Anthropic: Proxy tracking ---
echo "--- Anthropic (Proxy Tracking) ---"
ANTHROPIC_FILE="$USAGE_DIR/anthropic_proxy.jsonl"
if [ -f "$ANTHROPIC_FILE" ]; then
  node -e "
    const fs = require('fs');
    const lines = fs.readFileSync('$ANTHROPIC_FILE','utf8').trim().split('\n').filter(Boolean);
    const cutoff = new Date('$START_DATE').getTime();
    let total_input=0, total_output=0, total_cache_read=0, total_cache_create=0, requests=0;
    const byModel = {};
    for (const line of lines) {
      try {
        const r = JSON.parse(line);
        if (new Date(r.ts).getTime() < cutoff) continue;
        requests++;
        total_input += r.input_tokens || 0;
        total_output += r.output_tokens || 0;
        total_cache_read += r.cache_read_input_tokens || 0;
        total_cache_create += r.cache_creation_input_tokens || 0;
        const m = r.model || 'unknown';
        if (!byModel[m]) byModel[m] = {input:0,output:0,cache_read:0,requests:0};
        byModel[m].input += r.input_tokens || 0;
        byModel[m].output += r.output_tokens || 0;
        byModel[m].cache_read += r.cache_read_input_tokens || 0;
        byModel[m].requests++;
      } catch(e) {}
    }
    console.log('Requests: ' + requests);
    console.log('Input tokens: ' + total_input.toLocaleString());
    console.log('Output tokens: ' + total_output.toLocaleString());
    console.log('Cache read tokens: ' + total_cache_read.toLocaleString());
    console.log('Cache creation tokens: ' + total_cache_create.toLocaleString());
    console.log('Total tokens: ' + (total_input + total_output + total_cache_read + total_cache_create).toLocaleString());
    for (const [m, d] of Object.entries(byModel)) {
      console.log('  ' + m + ': ' + d.requests + ' reqs, ' + d.input.toLocaleString() + ' in, ' + d.output.toLocaleString() + ' out, ' + d.cache_read.toLocaleString() + ' cached');
    }
  "
else
  echo "(no proxy usage data yet)"
fi
echo ""

# --- Anthropic: Usage API (if admin key available) ---
echo "--- Anthropic (Usage API) ---"
ADMIN_KEY=$(bash "$VAULT" get anthropic-admin key 2>/dev/null || echo "")
if [ -n "$ADMIN_KEY" ]; then
  API_RESULT=$(curl -s "https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=${START_DATE}&ending_at=${END_DATE}&group_by[]=model&bucket_width=1d" \
    -H "anthropic-version: 2023-06-01" \
    -H "x-api-key: $ADMIN_KEY" 2>&1) || true

  node -e "
    const data = JSON.parse(process.argv[1]);
    if (data.error) {
      console.log('API error: ' + (data.error.message || JSON.stringify(data.error)));
    } else if (data.data) {
      let total_input=0, total_output=0, total_cache_read=0;
      for (const bucket of data.data) {
        total_input += bucket.input_tokens || 0;
        total_output += bucket.output_tokens || 0;
        total_cache_read += bucket.cache_read_input_tokens || 0;
        const m = bucket.model || 'all';
        console.log('  ' + (bucket.bucket_start_time||'').slice(0,10) + ' ' + m + ': ' + (bucket.input_tokens||0).toLocaleString() + ' in, ' + (bucket.output_tokens||0).toLocaleString() + ' out, ' + (bucket.cache_read_input_tokens||0).toLocaleString() + ' cached');
      }
      console.log('Totals: ' + total_input.toLocaleString() + ' in, ' + total_output.toLocaleString() + ' out, ' + total_cache_read.toLocaleString() + ' cached');
    } else {
      console.log('Unexpected response format');
    }
  " "$API_RESULT" 2>/dev/null || echo "Failed to parse Usage API response"
else
  echo "(no admin key in vault — add as 'anthropic-admin' with field 'key' to enable)"
  echo "(to create an admin key: Console → Settings → Admin Keys)"
fi
echo ""

# --- Gemini: Dispatch tracking ---
echo "--- Gemini (Dispatch Tracking) ---"
GEMINI_FILE="$USAGE_DIR/gemini_dispatch.jsonl"
if [ -f "$GEMINI_FILE" ]; then
  node -e "
    const fs = require('fs');
    const lines = fs.readFileSync('$GEMINI_FILE','utf8').trim().split('\n').filter(Boolean);
    const cutoff = new Date('$START_DATE').getTime();
    let total_prompt=0, total_completion=0, requests=0;
    const byScript = {};
    for (const line of lines) {
      try {
        const r = JSON.parse(line);
        if (new Date(r.ts).getTime() < cutoff) continue;
        requests++;
        total_prompt += r.prompt_tokens || 0;
        total_completion += r.completion_tokens || 0;
        const s = r.script || 'unknown';
        if (!byScript[s]) byScript[s] = {prompt:0,completion:0,requests:0};
        byScript[s].prompt += r.prompt_tokens || 0;
        byScript[s].completion += r.completion_tokens || 0;
        byScript[s].requests++;
      } catch(e) {}
    }
    console.log('Requests: ' + requests);
    console.log('Prompt tokens: ' + total_prompt.toLocaleString());
    console.log('Completion tokens: ' + total_completion.toLocaleString());
    console.log('Total tokens: ' + (total_prompt + total_completion).toLocaleString());
    for (const [s, d] of Object.entries(byScript)) {
      console.log('  ' + s + ': ' + d.requests + ' reqs, ' + d.prompt.toLocaleString() + ' prompt, ' + d.completion.toLocaleString() + ' completion');
    }
  "
else
  echo "(no Gemini dispatch usage data yet)"
fi
echo ""
echo "=== End Usage Report ==="
