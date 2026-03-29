#!/bin/bash
# log-gemini-usage.sh — Extract [gemini-usage] line from dispatch output and log it
# Usage: echo "$RESULT" | bash log-gemini-usage.sh <script_name>
# Reads from stdin, extracts Gemini usage, logs to JSONL, outputs cleaned result to stdout
SCRIPT_NAME="${1:-unknown}"
USAGE_DIR="/home/ubuntu/NanoClaw/data/usage"
mkdir -p "$USAGE_DIR"

INPUT=$(cat)

GEMINI_LINE=$(echo "$INPUT" | grep '^\[gemini-usage\]' | tail -1 | sed 's/^\[gemini-usage\] //')
if [ -n "$GEMINI_LINE" ]; then
  TS=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  # Merge script name and timestamp into the usage JSON
  echo "$GEMINI_LINE" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    d.ts='$TS'; d.script='$SCRIPT_NAME';
    console.log(JSON.stringify(d));
  " >> "$USAGE_DIR/gemini_dispatch.jsonl" 2>/dev/null || true
fi

# Output everything except the [gemini-usage] and [email-detail] and [email-triage] stderr lines
echo "$INPUT" | grep -v '^\[gemini-usage\]' | grep -v '^\[email-'
