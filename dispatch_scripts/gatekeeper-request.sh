#!/bin/bash
# gatekeeper-request.sh — Request approval from GateKeeper bot
# Usage: gatekeeper-request.sh '<action>' ['<details>']
# Returns: exit 0 if approved, exit 1 if denied/timeout
#
# This script is called by PhilClaw dispatch scripts.
# It writes a request file and polls for a response.
set -euo pipefail

ACTION="${1:?Usage: gatekeeper-request.sh '<action>' ['<details>']}"
DETAILS="${2:-}"
SOURCE="philclaw"

REQUESTS_DIR="/var/lib/gatekeeper/requests"
RESPONSES_DIR="/var/lib/gatekeeper/responses"
TIMEOUT=300  # 5 minutes

# Generate unique request ID
REQUEST_ID="req-$(date +%s)-$$"

# Write request file
cat > "${REQUESTS_DIR}/${REQUEST_ID}.json" << EOF
{
  "request_id": "${REQUEST_ID}",
  "action": "${ACTION}",
  "details": "${DETAILS}",
  "source": "${SOURCE}",
  "requested_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "Approval requested: ${ACTION}" >&2
echo "Waiting for GateKeeper response (${TIMEOUT}s timeout)..." >&2

# Poll for response
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  RESPONSE_FILE="${RESPONSES_DIR}/${REQUEST_ID}.json"
  if [ -f "$RESPONSE_FILE" ]; then
    APPROVED=$(python3 -c "import json; print(json.load(open('${RESPONSE_FILE}'))['approved'])")
    if [ "$APPROVED" = "True" ]; then
      echo "APPROVED" >&2
      echo "approved"
      exit 0
    else
      echo "DENIED" >&2
      echo "denied"
      exit 1
    fi
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

echo "TIMEOUT — auto-denied" >&2
echo "denied"
exit 1
