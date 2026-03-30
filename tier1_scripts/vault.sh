#!/bin/bash
# Credential vault management for NanoClaw Tier 1
# Uses age encryption. Never exposes credentials to LLM or containers.
set -euo pipefail

VAULT_DIR="$HOME/.config/nanoclaw/vault"
VAULT_FILE="$VAULT_DIR/credentials.age"
KEY_FILE="$VAULT_DIR/vault-key.txt"
PUBLIC_KEY=$(grep 'public key' "$KEY_FILE" | awk '{print $NF}')

decrypt_vault() {
  age -d -i "$KEY_FILE" "$VAULT_FILE"
}

encrypt_vault() {
  local tmp=$(mktemp)
  cat > "$tmp"
  age -r "$PUBLIC_KEY" -o "$VAULT_FILE" "$tmp"
  rm -f "$tmp"
}

cmd_list() {
  decrypt_vault | node -e "
    const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    for (const [k,v] of Object.entries(d)) {
      const type = v.type || 'unknown';
      const domains = (v.domains || []).join(', ');
      const desc = v.description || '';
      console.log(k + '  [' + type + ']  ' + (domains ? 'domains=' + domains + '  ' : '') + desc);
    }
    if (Object.keys(d).length === 0) console.log('(vault is empty)');
  "
}

cmd_get() {
  local name="$1"
  local field="${2:-}"
  decrypt_vault | node -e "
    const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const entry = d['$name'];
    if (!entry) { console.error('Not found: $name'); process.exit(1); }
    if ('$field') {
      const val = entry['$field'];
      if (val === undefined) { console.error('Field not found: $field'); process.exit(1); }
      process.stdout.write(String(val));
    } else {
      console.log(JSON.stringify(entry, null, 2));
    }
  "
}

cmd_set() {
  local name="$1"
  shift
  local result
  # Capture output in variable — if node fails, encrypt_vault never runs
  result=$(decrypt_vault | node -e "
    const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    if (!d['$name']) d['$name'] = {};
    const args = $(printf '%s\n' "$@" | node -e "
      const lines = require('fs').readFileSync('/dev/stdin','utf8').trim().split('\n');
      const obj = {};
      for (const line of lines) {
        const eq = line.indexOf('=');
        if (eq > 0) obj[line.slice(0,eq)] = line.slice(eq+1);
      }
      console.log(JSON.stringify(obj));
    ");
    Object.assign(d['$name'], args);
    console.log(JSON.stringify(d));
  ")
  echo "$result" | encrypt_vault
  echo "Updated: $name"
}

cmd_delete() {
  local name="$1"
  local result
  # Capture output in variable — if node fails (not found), encrypt_vault never runs
  result=$(decrypt_vault | node -e "
    const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    if (!d['$name']) { console.error('Not found: $name'); process.exit(1); }
    delete d['$name'];
    console.log(JSON.stringify(d));
  ")
  echo "$result" | encrypt_vault
  echo "Deleted: $name"
}

case "${1:-help}" in
  list)   cmd_list ;;
  get)    cmd_get "$2" "${3:-}" ;;
  set)    shift; cmd_set "$@" ;;
  delete) cmd_delete "$2" ;;
  help|*) echo "Usage: vault.sh {list|get <name> [field]|set <name> key=val ...|delete <name>}" ;;
esac
