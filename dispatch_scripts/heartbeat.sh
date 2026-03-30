#!/bin/bash
# heartbeat.sh — PhilClaw Heartbeat Daemon
# Runs periodic health checks and notifies Phil via Telegram when attention is needed.
# Usage: heartbeat.sh [--verbose]
#   --verbose: Always send Telegram message (even when all checks pass). Used for testing.
set -euo pipefail

VERBOSE="${1:-}"
WORKSPACE="/home/ubuntu/NanoClaw/groups/telegram_main"
HEARTBEAT_FILE="$WORKSPACE/HEARTBEAT.md"
MEMORY_FILE="$WORKSPACE/MEMORY.md"
OPS_LOG="/home/ubuntu/dispatch/ops-log.sh"

# Read bot token from NanoClaw .env
BOT_TOKEN=$(grep TELEGRAM_BOT_TOKEN /home/ubuntu/NanoClaw/.env | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | xargs)
CHAT_ID="8782115793"

ALERTS=""
STATUS_LINES=""
CHECKS_OK=0
CHECKS_FAIL=0

add_alert() {
  ALERTS="${ALERTS}• $1"$'\n'
  CHECKS_FAIL=$((CHECKS_FAIL + 1))
}

add_ok() {
  STATUS_LINES="${STATUS_LINES}✓ $1"$'\n'
  CHECKS_OK=$((CHECKS_OK + 1))
}

log() {
  bash "$OPS_LOG" "[HEARTBEAT] $1" 2>/dev/null || true
}

send_telegram() {
  local MSG="$1"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$MSG" \
    -d parse_mode=Markdown \
    > /dev/null 2>&1 || log "Failed to send Telegram heartbeat message"
}

# ============================================================
# HEALTH CHECKS
# ============================================================

# 1. Check NanoClaw service
if systemctl --user is-active nanoclaw >/dev/null 2>&1; then
  add_ok "NanoClaw service: running"
else
  add_alert "NanoClaw service: *NOT RUNNING*"
fi

# 2. Check Tier 2 (PortalClaw) SSH reachability
if ssh -o ConnectTimeout=5 -o BatchMode=yes tier2 'echo OK' >/dev/null 2>&1; then
  add_ok "Tier 2 (PortalClaw): reachable"
else
  add_alert "Tier 2 (PortalClaw): *UNREACHABLE*"
fi

# 3. Check Tier 3 (ReaderClaw) SSH reachability
if ssh -o ConnectTimeout=5 -o BatchMode=yes tier3 'echo OK' >/dev/null 2>&1; then
  add_ok "Tier 3 (ReaderClaw): reachable"
else
  add_alert "Tier 3 (ReaderClaw): *UNREACHABLE*"
fi

# 4. Check disk space on Tier 1 (alert if > 85% used)
DISK_PCT=$(df / --output=pcent | tail -1 | tr -d ' %')
if [ "$DISK_PCT" -gt 85 ]; then
  add_alert "Disk usage: *${DISK_PCT}%* (threshold: 85%)"
else
  add_ok "Disk usage: ${DISK_PCT}%"
fi

# 5. Check for memory reminders due today
TODAY=$(date '+%Y-%m-%d')
if [ -f "$MEMORY_FILE" ] && [ -s "$MEMORY_FILE" ]; then
  REMINDERS=$(grep -i "$TODAY" "$MEMORY_FILE" 2>/dev/null | head -3 || true)
  if [ -n "$REMINDERS" ]; then
    add_alert "Reminders due today: ${REMINDERS}"
  else
    add_ok "No reminders due today"
  fi
else
  add_ok "Memory file: empty (clean slate)"
fi

# 6. Check Docker daemon (needed for container sessions)
if docker info >/dev/null 2>&1; then
  add_ok "Docker daemon: running"
else
  add_alert "Docker daemon: *NOT RUNNING*"
fi

# ============================================================
# REPORT
# ============================================================

TOTAL=$((CHECKS_OK + CHECKS_FAIL))
TIMESTAMP=$(date '+%H:%M:%S %Z')

if [ "$CHECKS_FAIL" -gt 0 ]; then
  # Something needs attention — always notify
  MSG="*HEARTBEAT* ($TIMESTAMP)
⚠️ ${CHECKS_FAIL} issue(s) detected:

${ALERTS}
${CHECKS_OK}/${TOTAL} checks passed"
  log "ALERT — ${CHECKS_FAIL}/${TOTAL} failed"
  send_telegram "$MSG"

elif [ "$VERBOSE" = "--verbose" ]; then
  # All OK, but verbose mode — send status anyway (for testing)
  MSG="*HEARTBEAT* ($TIMESTAMP)
✓ All ${TOTAL} checks passed

${STATUS_LINES}"
  log "OK — All ${TOTAL} checks passed (verbose)"
  send_telegram "$MSG"

else
  # All OK, quiet mode — just log, no Telegram message
  log "OK — All ${TOTAL} checks passed"
fi
