#!/bin/bash
# portal-check.sh — Dispatch portal session to Tier 2 via full orchestration
# Usage: portal-check.sh <vault_portal_name> "<task_instructions>"
set -euo pipefail
OPS_LOG="/home/ubuntu/dispatch/ops-log.sh"

PORTAL="${1:-unknown}"
TASK="${2:-unknown}"

bash "$OPS_LOG" "Dispatching to Tier 2: portal check — $PORTAL — ${TASK:0:100}"

bash /home/ubuntu/scripts/dispatch_portal.sh "$@"
EXIT=$?

if [ $EXIT -eq 0 ]; then
  bash "$OPS_LOG" "Tier 2 portal check completed: $PORTAL"
else
  bash "$OPS_LOG" "Tier 2 portal check FAILED (exit $EXIT): $PORTAL"
fi

exit $EXIT
