#!/bin/bash
# SDK Timing Benchmark — measures Claude Code SDK + API latency sub-steps
# Outputs timing to stderr, result to stdout
set -euo pipefail

PROMPT="${1:-Reply with just the word PONG}"
MODEL="${2:-sonnet}"  # sonnet, haiku, opus
MAX_TURNS="${3:-1}"
RUN_ID="run-$(date +%s%3N)"

log() { echo "[bench $RUN_ID] $(date +%H:%M:%S.%3N) $1" >&2; }

log "=== SDK Timing Benchmark ==="
log "prompt: ${PROMPT:0:80}"
log "model: $MODEL"
log "max_turns: $MAX_TURNS"

# Step 1: Measure process spawn + SDK initialization
T_START=$(date +%s%3N)

# Use strace to capture subprocess activity (if available)
# But primarily measure via time markers in the output

# Step 2: Run claude --print with verbose output
T_INVOKE=$(date +%s%3N)
log "STEP invoke_claude: start (+$((T_INVOKE - T_START))ms from benchmark start)"

# Use --verbose to get internal timing, --output-format json for structured output
RESULT_FILE="/tmp/bench_result_${RUN_ID}.json"
STDERR_FILE="/tmp/bench_stderr_${RUN_ID}.txt"

# Run claude with timing capture
T_EXEC_START=$(date +%s%3N)
claude --print \
  --model "$MODEL" \
  --max-turns "$MAX_TURNS" \
  --output-format json \
  --verbose \
  "$PROMPT" \
  > "$RESULT_FILE" \
  2> "$STDERR_FILE" || true
T_EXEC_END=$(date +%s%3N)

log "STEP claude_complete: +$((T_EXEC_END - T_START))ms total, claude_exec=$((T_EXEC_END - T_EXEC_START))ms"

# Step 3: Parse the verbose stderr for internal timing markers
log "--- Internal SDK timing from stderr ---"
# Extract timing-related lines
grep -iE "timing|ms|latency|init|session|connect|model|token|start|ready|boot" "$STDERR_FILE" 2>/dev/null | head -30 | while read -r line; do
  log "  SDK: $line"
done

# Step 4: Parse the JSON result for token counts and model info
if [ -f "$RESULT_FILE" ] && [ -s "$RESULT_FILE" ]; then
  RESULT_LEN=$(wc -c < "$RESULT_FILE")
  log "result_size: ${RESULT_LEN} bytes"
  
  # Try to extract usage info from JSON
  python3 -c "
import json, sys
try:
    data = json.load(open('$RESULT_FILE'))
    if isinstance(data, dict):
        for k in ['usage', 'model', 'stop_reason', 'type']:
            if k in data:
                print(f'  {k}: {data[k]}')
    elif isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and item.get('type') == 'result':
                print(f'  model: {item.get(\"model\", \"?\")}')
                if 'usage' in item:
                    print(f'  usage: {item[\"usage\"]}')
except Exception as e:
    print(f'  parse error: {e}')
" 2>/dev/null | while read -r line; do
    log "  JSON: $line"
  done
else
  log "result: empty or missing"
fi

# Step 5: Analyze stderr for timing breakdown
log "--- Full stderr dump ---"
cat "$STDERR_FILE" 2>/dev/null | head -50 | while read -r line; do
  log "  ERR: $line"
done

# Summary
T_END=$(date +%s%3N)
log "=== SUMMARY ==="
log "total_wall_clock: $((T_END - T_START))ms"
log "claude_exec_time: $((T_EXEC_END - T_EXEC_START))ms"
log "overhead (pre+post): $((T_END - T_START - (T_EXEC_END - T_EXEC_START)))ms"

# Cleanup
rm -f "$RESULT_FILE" "$STDERR_FILE"
