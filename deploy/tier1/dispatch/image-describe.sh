#!/bin/bash
# image-describe.sh — Describe an image using Gemini vision via Tier 3
# Usage: image-describe.sh <image-path> [prompt]
# image-path: path to JPEG/PNG file on Tier 1
# prompt: optional custom prompt (default: general description)
set -euo pipefail
IMAGE_PATH="${1:?Usage: $0 <image-path> [prompt]}"
PROMPT="${2:-}"
VAULT="/home/ubuntu/NanoClaw/scripts/vault.sh"
OPS_LOG="/home/ubuntu/dispatch/ops-log.sh"

if [ ! -f "$IMAGE_PATH" ]; then
  echo "ERROR: Image file not found: $IMAGE_PATH"
  exit 1
fi

T_START=$(date +%s%3N)

T_VAULT=$(date +%s%3N)
GEMINI_KEY=$(bash "$VAULT" get gemini-api key)
T_VAULT_DONE=$(date +%s%3N)

# Detect MIME type
MIME="image/jpeg"
case "$IMAGE_PATH" in
  *.png) MIME="image/png" ;;
  *.gif) MIME="image/gif" ;;
  *.webp) MIME="image/webp" ;;
esac

# Base64 encode the image and pipe to Tier 3
T_SSH=$(date +%s%3N)
PROMPT_ENV=""
if [ -n "$PROMPT" ]; then
  PROMPT_ENV="IMAGE_PROMPT='$(echo "$PROMPT" | sed "s/'/'\\\\''/g")'"
fi

RESULT=$(base64 -w0 "$IMAGE_PATH" | ssh tier3 "GEMINI_API_KEY='$GEMINI_KEY' IMAGE_MIME='$MIME' $PROMPT_ENV NODE_PATH=/usr/lib/node_modules node /home/ubuntu/scripts/describe_image.js" 2>&1) || true
T_SSH_DONE=$(date +%s%3N)

bash "$OPS_LOG" "Image describe: vault=$((T_VAULT_DONE-T_VAULT))ms ssh+gemini=$((T_SSH_DONE-T_SSH))ms total=$((T_SSH_DONE-T_START))ms (${#RESULT} chars)"

echo "$RESULT" | bash "$(dirname "$0")/log-gemini-usage.sh" image-describe
