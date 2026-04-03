#!/bin/bash
# order-history-search.sh — Search Amazon order history CSV
# Usage: order-history-search.sh '<query>'
# Searches product names (case-insensitive) and returns matching orders
set -euo pipefail

QUERY="${1:-}"
if [ -z "$QUERY" ]; then
  echo "ERROR: search query required" >&2
  exit 1
fi

CSV="/home/ubuntu/NanoClaw/data/amazon_order_history.csv"
if [ ! -f "$CSV" ]; then
  echo "ERROR: order history not found at $CSV" >&2
  exit 1
fi

# Use python for proper CSV parsing
python3 -c "
import csv, sys, re

query = '''$QUERY'''.lower()
results = []

with open('$CSV') as f:
    reader = csv.DictReader(f)
    for r in reader:
        name = r.get('product_name', '')
        if query in name.lower():
            results.append(r)

# Sort by date descending
results.sort(key=lambda r: r.get('order_date', ''), reverse=True)

for r in results[:20]:
    date = r.get('order_date', '?')
    acct = r.get('account', '?')
    asin = r.get('asin', '?')
    price = r.get('unit_price', '?')
    name = r.get('product_name', '?')[:150]
    print(f'- {date} | {acct} | ASIN: {asin} | \${price} | {name}')

print(f'')
print(f'({len(results)} matches found for \"{query}\")')
"
