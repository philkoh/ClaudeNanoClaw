#!/bin/bash
# Trace what the SDK does during the 104-second gap
# Monitors CPU, IO, network, and process activity in parallel with the benchmark
set -euo pipefail

CONTAINER="nanoclaw-telegram-main-1774635874497"
TRACE_DIR="/tmp/sdk_trace_$(date +%s)"
mkdir -p "$TRACE_DIR"

echo "[trace] Starting system monitoring in background..."

# Monitor 1: CPU and memory every 2 seconds
docker exec "$CONTAINER" sh -c '
  while true; do
    echo "$(date +%H:%M:%S.%3N) $(cat /proc/loadavg) MEM=$(awk "/MemAvailable/{print \$2}" /proc/meminfo)kB"
    sleep 2
  done
' > "$TRACE_DIR/cpu_mem.log" 2>&1 &
MON1_PID=$!

# Monitor 2: Network activity (bytes sent/recv) every 2 seconds
docker exec "$CONTAINER" sh -c '
  PREV_RX=0; PREV_TX=0
  while true; do
    RX=$(cat /proc/net/dev | grep eth0 | awk "{print \$2}")
    TX=$(cat /proc/net/dev | grep eth0 | awk "{print \$10}")
    DRX=$((RX - PREV_RX)); DTX=$((TX - PREV_TX))
    echo "$(date +%H:%M:%S.%3N) rx_delta=${DRX}B tx_delta=${DTX}B rx_total=${RX}B tx_total=${TX}B"
    PREV_RX=$RX; PREV_TX=$TX
    sleep 2
  done
' > "$TRACE_DIR/network.log" 2>&1 &
MON2_PID=$!

# Monitor 3: Process activity — what node processes are running
docker exec "$CONTAINER" sh -c '
  while true; do
    echo "=== $(date +%H:%M:%S.%3N) ==="
    ps aux --sort=-%cpu 2>/dev/null | head -10
    echo ""
    sleep 3
  done
' > "$TRACE_DIR/processes.log" 2>&1 &
MON3_PID=$!

# Monitor 4: File system activity via inotifywait (if available) or strace
docker exec "$CONTAINER" sh -c '
  while true; do
    echo "$(date +%H:%M:%S.%3N) OPEN_FILES=$(ls /proc/1/fd 2>/dev/null | wc -l) NODE_PROCS=$(pgrep -c node 2>/dev/null || echo 0)"
    sleep 2
  done
' > "$TRACE_DIR/fd_count.log" 2>&1 &
MON4_PID=$!

echo "[trace] Monitors started. Running benchmark..."

# Run the actual benchmark
T0=$(date +%s%3N)
docker exec -w /app "$CONTAINER" node /app/container_sdk_bench.mjs "Reply with just PONG" 1 > "$TRACE_DIR/bench_stdout.json" 2> "$TRACE_DIR/bench_stderr.txt"
T1=$(date +%s%3N)

echo "[trace] Benchmark complete: $((T1-T0))ms"

# Kill monitors
kill $MON1_PID $MON2_PID $MON3_PID $MON4_PID 2>/dev/null || true
wait 2>/dev/null

echo ""
echo "=== BENCHMARK TIMING ==="
cat "$TRACE_DIR/bench_stderr.txt"

echo ""
echo "=== CPU/MEM TRACE ==="
cat "$TRACE_DIR/cpu_mem.log"

echo ""
echo "=== NETWORK TRACE ==="
cat "$TRACE_DIR/network.log"

echo ""
echo "=== PROCESS TRACE (first 40 lines) ==="
head -40 "$TRACE_DIR/processes.log"

echo ""
echo "=== FD COUNT TRACE ==="
cat "$TRACE_DIR/fd_count.log"

rm -rf "$TRACE_DIR"
