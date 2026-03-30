#!/bin/bash
# close_portal.sh — Called by Tier 1 orchestrator via SSH on Tier 2
# Clears Squid whitelist and kills any running OpenClaw sessions
set -euo pipefail

WHITELIST="/etc/squid/whitelist.txt"

# Clear the whitelist
sudo truncate -s 0 "$WHITELIST"
sudo squid -k reconfigure

# Stop any running OpenClaw containers (except the gateway if running)
CONTAINERS=$(docker ps -q --filter "label=openclaw-session" 2>/dev/null || true)
if [ -n "$CONTAINERS" ]; then
  docker stop $CONTAINERS 2>/dev/null || true
  docker rm $CONTAINERS 2>/dev/null || true
  echo "Stopped OpenClaw session containers"
fi

echo "Portal closed. Whitelist cleared."
