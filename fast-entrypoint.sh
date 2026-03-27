#!/bin/bash
set -e
cd /app

T0=$(date +%s%3N)

# Hash source to check if recompilation needed
DIST_DIR="/home/node/.claude/tsc-cache"
mkdir -p "$DIST_DIR"
SRC_HASH=$(md5sum src/index.ts src/ipc-mcp-stdio.ts 2>/dev/null | md5sum | cut -d" " -f1)
CACHE_HASH=""
[ -f "$DIST_DIR/.src-hash" ] && CACHE_HASH=$(cat "$DIST_DIR/.src-hash")

T1=$(date +%s%3N)

if [ "$SRC_HASH" != "$CACHE_HASH" ] || [ ! -f "$DIST_DIR/index.js" ]; then
  echo "[entrypoint] tsc: COMPILING (cache miss)" >&2
  npx tsc --outDir "$DIST_DIR" 2>&1 >&2
  echo "$SRC_HASH" > "$DIST_DIR/.src-hash"
else
  echo "[entrypoint] tsc: CACHE HIT (skipped)" >&2
fi

[ -e "$DIST_DIR/node_modules" ] || ln -sf /app/node_modules "$DIST_DIR/node_modules"

T2=$(date +%s%3N)
FREE_KB=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
echo "[entrypoint] timing: hash=$((T1-T0))ms tsc=$((T2-T1))ms total_boot=$((T2-T0))ms freemem=${FREE_KB}kB" >&2

cat > /tmp/input.json
T3=$(date +%s%3N)
echo "[entrypoint] input_wait=$((T3-T2))ms launching node..." >&2
node "$DIST_DIR/index.js" < /tmp/input.json
