#!/bin/bash
# agent-gateway.sh — Restricted SSH gateway for NanoClaw container agent
# Only allows execution of approved dispatch scripts with validated arguments.
# SSH forced command: the actual command is in $SSH_ORIGINAL_COMMAND
set -euo pipefail

CMD="${SSH_ORIGINAL_COMMAND:-}"
if [ -z "$CMD" ]; then
  echo "ERROR: No command provided" >&2
  exit 1
fi

# Reject any command containing shell metacharacters that could chain commands
# This blocks: ; | & ` $() ${ } < > newlines
case "$CMD" in
  *\;*|*\|*|*\&*|*\`*|*\$\(*|*\$\{*|*\<*|*\>*)
    echo "ERROR: Illegal characters in command" >&2
    exit 1
    ;;
esac

# Parse command into script path and arguments
# Expected format: bash /home/ubuntu/dispatch/<script>.sh [args...]
# or: bash /home/ubuntu/NanoClaw/scripts/vault.sh list
read -r INTERPRETER SCRIPT_PATH ARGS <<< "$CMD"

if [ "$INTERPRETER" != "bash" ]; then
  echo "ERROR: Only bash interpreter allowed" >&2
  exit 1
fi

case "$SCRIPT_PATH" in
  /home/ubuntu/dispatch/email-summary.sh)
    # Args: optional count (integer only)
    if [ -n "$ARGS" ] && ! [[ "$ARGS" =~ ^[0-9]+$ ]]; then
      echo "ERROR: email-summary.sh accepts only an integer count" >&2
      exit 1
    fi
    exec bash "$SCRIPT_PATH" $ARGS
    ;;
  /home/ubuntu/dispatch/email-detail.sh)
    # Args: [--interpret <base64_prompt>] <query> [max_results]
    # Interpret prompt is base64-encoded to avoid quoting issues
    if [ -z "$ARGS" ]; then
      echo "ERROR: email-detail.sh requires a search query" >&2
      exit 1
    fi
    exec bash "$SCRIPT_PATH" $ARGS
    ;;
  /home/ubuntu/dispatch/web-search.sh)
    # Args: single quoted search query
    if [ -z "$ARGS" ]; then
      echo "ERROR: web-search.sh requires a query argument" >&2
      exit 1
    fi
    exec bash "$SCRIPT_PATH" "$ARGS"
    ;;
  /home/ubuntu/dispatch/portal-check.sh)
    # Args: portal_name task_instructions
    if [ -z "$ARGS" ]; then
      echo "ERROR: portal-check.sh requires portal_name and task" >&2
      exit 1
    fi
    exec bash "$SCRIPT_PATH" $ARGS
    ;;
  /home/ubuntu/dispatch/usage-report.sh)
    # Args: optional days (integer only)
    if [ -n "$ARGS" ] && ! [[ "$ARGS" =~ ^[0-9]+$ ]]; then
      echo "ERROR: usage-report.sh accepts only an integer day count" >&2
      exit 1
    fi
    exec bash "$SCRIPT_PATH" $ARGS
    ;;
  /home/ubuntu/dispatch/ops-log.sh)
    # Args: message string
    if [ -z "$ARGS" ]; then
      echo "ERROR: ops-log.sh requires a message" >&2
      exit 1
    fi
    exec bash "$SCRIPT_PATH" "$ARGS"
    ;;
  /home/ubuntu/NanoClaw/scripts/vault.sh)
    # Only allow "list" subcommand
    if [ "$ARGS" != "list" ]; then
      echo "ERROR: vault.sh only allows 'list' subcommand" >&2
      exit 1
    fi
    exec bash "$SCRIPT_PATH" list
    ;;
  *)
    echo "ERROR: Script not allowed: $SCRIPT_PATH" >&2
    exit 1
    ;;
esac
