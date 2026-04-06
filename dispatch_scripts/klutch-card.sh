#!/bin/bash
# klutch-card.sh — Manage Klutch Spend Card via GraphQL API
# Subcommands: auth, read-spend, set-cap, lock, read-state
# set-cap requires GateKeeper approval
set -euo pipefail

VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
GATEKEEPER="/home/ubuntu/dispatch/gatekeeper-request.sh"
ENDPOINT="https://graphql.klutchcard.com/graphql"
SUBCOMMAND="${1:?Usage: klutch-card.sh <auth|read-spend|set-cap|lock|read-state> [args...]}"
shift

# Get session token
get_token() {
  local CLIENT_ID=$(bash "$VAULT" get klutch-card client_id)
  local SECRET_KEY=$(bash "$VAULT" get klutch-card secret_key)
  local RESULT=$(curl -s -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"mutation{createSessionToken(clientId:\\\"$CLIENT_ID\\\",secretKey:\\\"$SECRET_KEY\\\")}\"}")
  echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['createSessionToken'])"
}

gql() {
  local TOKEN="$1"
  local QUERY="$2"
  curl -s -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "$QUERY"
}

case "$SUBCOMMAND" in
  auth)
    TOKEN=$(get_token)
    echo "Session token obtained (${#TOKEN} chars)"
    ;;

  read-spend)
    CARD_ID="${1:?Usage: klutch-card.sh read-spend <card_id>}"
    TOKEN=$(get_token)
    RESULT=$(gql "$TOKEN" '{"query":"query{sumTransactions(filter:{cardIds:[\"'$CARD_ID'\"],transactionStatus:[\"PENDING\",\"SETTLED\"],transactionTypes:[\"CHARGE\"]})}"}')
    echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Total spend: \${d[\"data\"][\"sumTransactions\"]:.2f}')"
    ;;

  set-cap)
    CARD_ID="${1:?Usage: klutch-card.sh set-cap <card_id> <limit_amount> <description>}"
    LIMIT="${2:?Missing limit amount}"
    DESC="${3:-Purchase}"

    # REQUIRE GATEKEEPER APPROVAL
    APPROVAL=$(bash "$GATEKEEPER" "Set Klutch spend cap to \$$LIMIT" "$DESC" 2>/dev/null) || true
    if [ "$APPROVAL" != "approved" ]; then
      echo "ERROR: GateKeeper denied or timed out"
      exit 1
    fi

    TOKEN=$(get_token)
    # Delete existing cap rule if any
    RULES=$(gql "$TOKEN" '{"query":"query{transactionRules{id name cards{id}}}"}')
    OLD_RULE_ID=$(echo "$RULES" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('data',{}).get('transactionRules',[]):
  if 'spend-cap' in r.get('name','') and any(c['id']=='$CARD_ID' for c in r.get('cards',[])):
    print(r['id']); break
" 2>/dev/null || true)

    if [ -n "$OLD_RULE_ID" ]; then
      gql "$TOKEN" "{\"query\":\"mutation{transactionRule(id:\\\"$OLD_RULE_ID\\\"){delete}}\"}" > /dev/null
    fi

    # Create new cap rule
    RESULT=$(gql "$TOKEN" "{\"query\":\"mutation{createTransactionRule(name:\\\"spend-cap-$CARD_ID\\\",displayName:\\\"Bot Spend Cap\\\",cardIds:[\\\"$CARD_ID\\\"],spec:{specType:\\\"StartEndDateTransactionRule\\\",startDate:\\\"2026-01-01T00:00:00Z\\\",endDate:\\\"2036-01-01T00:00:00Z\\\",limitAmount:$LIMIT}){id}}\"}")
    echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Spend cap set to \$$LIMIT — rule ID: {d[\"data\"][\"createTransactionRule\"][\"id\"]}')"
    ;;

  lock)
    CARD_ID="${1:?Usage: klutch-card.sh lock <card_id>}"
    TOKEN=$(get_token)
    RESULT=$(gql "$TOKEN" "{\"query\":\"mutation{card(id:\\\"$CARD_ID\\\"){lock{id status}}}\"}")
    echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Card locked: {d[\"data\"][\"card\"][\"lock\"][\"status\"]}')"
    ;;

  read-state)
    TOKEN=$(get_token)
    RESULT=$(gql "$TOKEN" '{"query":"query{cards{id name status lockState lastFour}}"}')
    echo "$RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d.get('data',{}).get('cards',[]):
  print(f'{c[\"name\"]} (****{c[\"lastFour\"]}) — status: {c[\"status\"]}, lock: {c[\"lockState\"]}')
"
    ;;

  *)
    echo "ERROR: Unknown subcommand: $SUBCOMMAND"
    echo "Usage: klutch-card.sh <auth|read-spend|set-cap|lock|read-state> [args...]"
    exit 1
    ;;
esac
