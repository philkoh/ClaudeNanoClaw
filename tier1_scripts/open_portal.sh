#!/bin/bash
# open_portal.sh — Called by Tier 1 orchestrator via SSH on Tier 2
# Opens Squid whitelist for a portal domain, enabling egress
# Usage: open_portal.sh <domain> [additional_domains...]
set -euo pipefail

WHITELIST="/etc/squid/whitelist.txt"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <domain> [domain2 ...]" >&2
  exit 1
fi

# Clear existing whitelist and add new domains
# Squid dstdomain matches the domain and all subdomains automatically
sudo truncate -s 0 "$WHITELIST"
for domain in "$@"; do
  echo "$domain" | sudo tee -a "$WHITELIST" > /dev/null
done

# Reload Squid to pick up new whitelist
sudo squid -k reconfigure

echo "Portal opened for: $*"
cat "$WHITELIST"
