#!/usr/bin/env node
/**
 * Claude Code SDK Sub-Step Timing Benchmark
 * Measures every phase of a query() call to tenths of a second:
 *   1. Module import time
 *   2. query() call overhead (before first API message)
 *   3. System/init message (session creation)
 *   4. Time to first assistant token (TTFB from API)
 *   5. Assistant streaming duration
 *   6. Tool execution time (if any)
 *   7. Result assembly
 *   8. Total wall clock
 */

const T_SCRIPT_START = performance.now();

// Phase 1: Module import
const T_IMPORT_START = performance.now();

// Dynamic import to measure load time
const { query } = await import('/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js').catch(async () => {
  // Fallback: use subprocess
  return { query: null };
});

const T_IMPORT_END = performance.now();

// If query is null, we'll use the CLI approach
if (!query) {
  console.error('[bench] query() not exported from cli.js, using CLI subprocess approach');

  const { execSync } = await import('child_process');
  const { performance: perf } = await import('perf_hooks');

  const PROMPT = process.argv[2] || 'Reply with just the word PONG';
  const MODEL = process.argv[3] || 'sonnet';

  const runs = parseInt(process.argv[4] || '3');
  const results = [];

  for (let i = 0; i < runs; i++) {
    const t0 = perf.now();
    try {
      execSync(`claude --print --model ${MODEL} --max-turns 1 "${PROMPT}"`, {
        timeout: 180000,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
    } catch (e) {
      // May throw if exit code non-zero but still produces output
    }
    const t1 = perf.now();
    results.push(t1 - t0);
    console.error(`[bench] CLI run ${i+1}/${runs}: ${((t1-t0)/1000).toFixed(1)}s`);
  }

  console.error(`[bench] CLI avg: ${(results.reduce((a,b)=>a+b,0)/results.length/1000).toFixed(1)}s`);
  process.exit(0);
}

console.error(`[bench] Module import: ${((T_IMPORT_END - T_IMPORT_START)/1000).toFixed(1)}s`);

// Phase 2-8: Run query with message-level timing
const PROMPT = process.argv[2] || 'Reply with just the word PONG';
const MODEL = process.argv[3] || 'sonnet';
const RUNS = parseInt(process.argv[4] || '3');

async function benchmarkRun(runNum) {
  const timing = {
    run: runNum,
    prompt: PROMPT.slice(0, 60),
    model: MODEL,
    query_call_start: 0,
    first_system_msg: 0,
    session_init: 0,
    first_assistant_msg: 0,
    first_result: 0,
    query_complete: 0,
    messages: [],
    tool_uses: [],
  };

  const T_QUERY_START = performance.now();
  timing.query_call_start = T_QUERY_START;

  let msgCount = 0;
  let firstAssistantTime = 0;
  let firstSystemTime = 0;
  let sessionInitTime = 0;
  let firstResultTime = 0;
  let lastToolStartTime = 0;
  let totalToolTime = 0;

  try {
    for await (const message of query({
      prompt: PROMPT,
      options: {
        model: MODEL,
        maxTurns: 1,
        permissionMode: 'bypassPermissions',
        allowDangerouslySkipPermissions: true,
        systemPrompt: 'You are a benchmark test. Respond as briefly as possible.',
        allowedTools: [],  // No tools = pure API timing
      }
    })) {
      const now = performance.now();
      const elapsed = ((now - T_QUERY_START) / 1000).toFixed(1);
      msgCount++;

      const msgType = message.type === 'system'
        ? `system/${message.subtype || '?'}`
        : message.type;

      timing.messages.push({
        seq: msgCount,
        type: msgType,
        elapsed_s: parseFloat(elapsed),
        delta_ms: msgCount === 1 ? 0 : Math.round(now - (timing.messages[timing.messages.length - 1]?._absTime || T_QUERY_START)),
        _absTime: now,
      });

      // Track key milestones
      if (message.type === 'system' && !firstSystemTime) {
        firstSystemTime = now;
        timing.first_system_msg = parseFloat(elapsed);
      }
      if (message.type === 'system' && message.subtype === 'init') {
        sessionInitTime = now;
        timing.session_init = parseFloat(elapsed);
        console.error(`[bench run#${runNum}] +${elapsed}s session_init (session_id: ${message.session_id?.slice(0,12)}...)`);
      }
      if (message.type === 'assistant' && !firstAssistantTime) {
        firstAssistantTime = now;
        timing.first_assistant_msg = parseFloat(elapsed);
        console.error(`[bench run#${runNum}] +${elapsed}s first_assistant (TTFB from API)`);
      }
      if (message.type === 'result' && !firstResultTime) {
        firstResultTime = now;
        timing.first_result = parseFloat(elapsed);

        const resultText = message.result || '';
        console.error(`[bench run#${runNum}] +${elapsed}s result (${resultText.length} chars): ${resultText.slice(0, 100)}`);
      }
    }
  } catch (err) {
    console.error(`[bench run#${runNum}] ERROR: ${err.message}`);
    timing.error = err.message;
  }

  const T_QUERY_END = performance.now();
  timing.query_complete = parseFloat(((T_QUERY_END - T_QUERY_START) / 1000).toFixed(1));

  // Clean up internal fields
  timing.messages.forEach(m => delete m._absTime);

  // Compute sub-step durations
  timing.breakdown = {
    sdk_init_to_session: timing.session_init,
    session_to_first_assistant: timing.first_assistant_msg
      ? parseFloat((timing.first_assistant_msg - timing.session_init).toFixed(1))
      : null,
    first_assistant_to_result: timing.first_result && timing.first_assistant_msg
      ? parseFloat((timing.first_result - timing.first_assistant_msg).toFixed(1))
      : null,
    total: timing.query_complete,
  };

  return timing;
}

console.error(`\n${'='.repeat(60)}`);
console.error(`Claude Code SDK Sub-Step Timing Benchmark`);
console.error(`Model: ${MODEL} | Prompt: "${PROMPT.slice(0,50)}" | Runs: ${RUNS}`);
console.error(`${'='.repeat(60)}\n`);

const allResults = [];

for (let i = 1; i <= RUNS; i++) {
  console.error(`\n--- Run ${i}/${RUNS} ---`);
  const result = await benchmarkRun(i);
  allResults.push(result);

  console.error(`[bench run#${i}] COMPLETE: total=${result.query_complete}s`);
  console.error(`  breakdown: sdk_init=${result.breakdown.sdk_init_to_session}s → API_TTFB=${result.breakdown.session_to_first_assistant}s → streaming=${result.breakdown.first_assistant_to_result}s`);
}

// Summary
console.error(`\n${'='.repeat(60)}`);
console.error(`SUMMARY (${RUNS} runs)`);
console.error(`${'='.repeat(60)}`);

const totals = allResults.map(r => r.query_complete);
const sdkInits = allResults.map(r => r.breakdown.sdk_init_to_session);
const ttfbs = allResults.map(r => r.breakdown.session_to_first_assistant).filter(v => v !== null);
const streams = allResults.map(r => r.breakdown.first_assistant_to_result).filter(v => v !== null);

const avg = arr => arr.length ? (arr.reduce((a,b) => a+b, 0) / arr.length).toFixed(1) : 'N/A';
const min = arr => arr.length ? Math.min(...arr).toFixed(1) : 'N/A';
const max = arr => arr.length ? Math.max(...arr).toFixed(1) : 'N/A';

console.error(`\nModule import:      ${((T_IMPORT_END - T_IMPORT_START)/1000).toFixed(1)}s (one-time)`);
console.error(`SDK init→session:   avg=${avg(sdkInits)}s  min=${min(sdkInits)}s  max=${max(sdkInits)}s`);
console.error(`Session→1st asst:   avg=${avg(ttfbs)}s  min=${min(ttfbs)}s  max=${max(ttfbs)}s  (API TTFB)`);
console.error(`1st asst→result:    avg=${avg(streams)}s  min=${min(streams)}s  max=${max(streams)}s  (streaming)`);
console.error(`Total per query:    avg=${avg(totals)}s  min=${min(totals)}s  max=${max(totals)}s`);

// Output JSON for analysis
console.log(JSON.stringify({
  benchmark: 'claude-code-sdk-substep',
  timestamp: new Date().toISOString(),
  module_import_s: parseFloat(((T_IMPORT_END - T_IMPORT_START)/1000).toFixed(1)),
  runs: allResults
}, null, 2));
