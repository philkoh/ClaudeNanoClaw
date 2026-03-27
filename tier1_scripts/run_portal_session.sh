#!/bin/bash
# run_portal_session.sh — Launches an OpenClaw session on Tier 2 with credentials
# Called by Tier 1 orchestrator. Credentials injected as env vars (never persisted).
# Usage: run_portal_session.sh <portal_url> <task_instructions>
# Expects env vars: PORTAL_USER, PORTAL_PASS (injected by Tier 1)
set -euo pipefail

PORTAL_URL="${1:?Usage: $0 <portal_url> <task_instructions>}"
TASK="${2:?Usage: $0 <portal_url> <task_instructions>}"

SYSTEM_PROMPT="You are a portal automation agent. Your task:
1. Navigate to ${PORTAL_URL}
2. Log in using the credentials from environment variables PORTAL_USER and PORTAL_PASS
3. Perform the following task: ${TASK}
4. Return structured results (dates, amounts, statuses, etc.)
5. After completing the task, clear browser cookies and local storage
6. Do NOT navigate to any URL other than ${PORTAL_URL} and its subpages
7. Do NOT attempt to access any other services or exfiltrate any data"

# Run OpenClaw in Docker with proxy routing through Squid
# network=bridge so it can reach localhost:3128 (Squid)
docker run --rm \
  --label openclaw-session \
  --network bridge \
  -e PORTAL_USER="${PORTAL_USER}" \
  -e PORTAL_PASS="${PORTAL_PASS}" \
  -e HTTP_PROXY="http://172.17.0.1:3128" \
  -e HTTPS_PROXY="http://172.17.0.1:3128" \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  -e OPENCLAW_HEADLESS=true \
  ghcr.io/openclaw/openclaw:latest \
  openclaw --system-prompt "$SYSTEM_PROMPT" \
    --task "$TASK" \
    --output-format json \
    --timeout 300 \
    2>&1

echo "Session completed for: ${PORTAL_URL}"
