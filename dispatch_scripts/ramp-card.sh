#!/bin/bash
# ramp-card.sh — Manage Ramp corporate card via REST API
# Subcommands: auth, read-spend, set-limit, read-txns, read-state
# set-limit requires GateKeeper approval
set -euo pipefail

VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
GATEKEEPER="/home/ubuntu/dispatch/gatekeeper-request.sh"
API="https://api.ramp.com/developer/v1"
SUBCOMMAND="${1:?Usage: ramp-card.sh <auth|read-spend|set-limit|read-txns|read-state> [args...]}"
shift

# Get OAuth token
get_token() {
  local CLIENT_ID=$(bash "$VAULT" get ramp-business client_id)
  local CLIENT_SECRET=$(bash "$VAULT" get ramp-business client_secret)
  local RESULT=$(curl -s -X POST "$API/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&scope=limits:read limits:write transactions:read")
  echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])"
}

api_get() {
  local TOKEN="$1"
  local PATH="$2"
  curl -s -H "Authorization: Bearer $TOKEN" "$API$PATH"
}

api_patch() {
  local TOKEN="$1"
  local PATH="$2"
  local BODY="$3"
  curl -s -X PATCH -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$API$PATH" -d "$BODY"
}

case "$SUBCOMMAND" in
  auth)
    TOKEN=$(get_token)
    echo "OAuth token obtained (${#TOKEN} chars)"
    ;;

  read-spend)
    LIMIT_ID="${1:?Usage: ramp-card.sh read-spend <spend_limit_id>}"
    TOKEN=$(get_token)
    RESULT=$(api_get "$TOKEN" "/limits/$LIMIT_ID")
    echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
bal = d.get('balance',{})
total = bal.get('total',{}).get('amount',0) / 100
cleared = bal.get('cleared',{}).get('amount',0) / 100
pending = bal.get('pending',{}).get('amount',0) / 100
limit = d.get('spending_restrictions',{}).get('limit',{}).get('amount',0) / 100
print(f'Limit: \${limit:.2f}')
print(f'Total spend: \${total:.2f} (cleared: \${cleared:.2f}, pending: \${pending:.2f})')
print(f'Remaining: \${limit - total:.2f}')
"
    ;;

  set-limit)
    LIMIT_ID="${1:?Usage: ramp-card.sh set-limit <spend_limit_id> <amount_cents> <description>}"
    AMOUNT_CENTS="${2:?Missing amount in cents}"
    DESC="${3:-Purchase}"
    AMOUNT_DOLLARS=$(python3 -c "print(f'{$AMOUNT_CENTS/100:.2f}')")

    # REQUIRE GATEKEEPER APPROVAL
    APPROVAL=$(bash "$GATEKEEPER" "Set Ramp spend limit to \$$AMOUNT_DOLLARS" "$DESC" 2>/dev/null) || true
    if [ "$APPROVAL" != "approved" ]; then
      echo "ERROR: GateKeeper denied or timed out"
      exit 1
    fi

    TOKEN=$(get_token)
    RESULT=$(api_patch "$TOKEN" "/limits/$LIMIT_ID" "{\"spending_restrictions\":{\"limit\":{\"amount\":$AMOUNT_CENTS,\"currency_code\":\"USD\"}}}")
    echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
new_limit = d.get('spending_restrictions',{}).get('limit',{}).get('amount',0) / 100
print(f'Limit set to: \${new_limit:.2f}')
"
    ;;

  read-txns)
    LIMIT_ID="${1:-}"
    TOKEN=$(get_token)
    FILTER=""
    if [ -n "$LIMIT_ID" ]; then
      FILTER="?limit_id=$LIMIT_ID"
    fi
    RESULT=$(api_get "$TOKEN" "/transactions$FILTER")
    echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d.get('data',[])[:10]:
  amt = t.get('amount',0) / 100
  merchant = t.get('merchant_name','Unknown')
  state = t.get('state','?')
  date = t.get('user_transaction_time','?')[:10]
  print(f'  {date} | \${amt:.2f} | {merchant} | {state}')
if not d.get('data'):
  print('No transactions found')
"
    ;;

  read-state)
    LIMIT_ID="${1:?Usage: ramp-card.sh read-state <spend_limit_id>}"
    TOKEN=$(get_token)
    RESULT=$(api_get "$TOKEN" "/limits/$LIMIT_ID")
    echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f'Display name: {d.get(\"display_name\",\"?\")}')
print(f'State: {d.get(\"state\",\"?\")}')
bal = d.get('balance',{})
total = bal.get('total',{}).get('amount',0) / 100
limit = d.get('spending_restrictions',{}).get('limit',{}).get('amount',0) / 100
print(f'Limit: \${limit:.2f} | Spent: \${total:.2f} | Remaining: \${limit - total:.2f}')
"
    ;;

  *)
    echo "ERROR: Unknown subcommand: $SUBCOMMAND"
    echo "Usage: ramp-card.sh <auth|read-spend|set-limit|read-txns|read-state> [args...]"
    exit 1
    ;;
esac
