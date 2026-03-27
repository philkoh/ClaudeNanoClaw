/**
 * In-Container Claude Agent SDK Timing Benchmark
 * Run inside the nanoclaw container to measure query() sub-steps
 *
 * Timing points (all in seconds to 0.1s precision):
 *   T0: Script start
 *   T1: Module import complete
 *   T2: query() called
 *   T3: First system message (any)
 *   T4: system/init message (session created)
 *   T5: First assistant message (API TTFB)
 *   T6: Result message received
 *   T7: query() iterator exhausted (complete)
 */

const T0 = performance.now();
const ts = (label) => {
  const elapsed = ((performance.now() - T0) / 1000).toFixed(1);
  const abs = new Date().toISOString().slice(11, 23);
  console.error(`[TIMING] +${elapsed.padStart(6)}s  ${abs}  ${label}`);
  return performance.now();
};

ts('script_start');

// Phase 1: Import
const T_IMPORT_START = performance.now();
const { query } = await import('@anthropic-ai/claude-agent-sdk');
const T_IMPORT_END = performance.now();
ts(`import_complete (${((T_IMPORT_END - T_IMPORT_START)/1000).toFixed(1)}s)`);

// Phase 2: Prepare
const PROMPT = process.argv[2] || 'Reply with just the word PONG. Nothing else.';
const RUNS = parseInt(process.argv[3] || '3');
const USE_TOOLS = process.argv[4] === 'tools';

console.error(`[CONFIG] prompt="${PROMPT.slice(0,60)}" runs=${RUNS} tools=${USE_TOOLS}`);

const allRuns = [];

for (let run = 1; run <= RUNS; run++) {
  console.error(`\n${'─'.repeat(50)}`);
  console.error(`[RUN ${run}/${RUNS}]`);

  const milestones = {};
  const messages = [];
  const RUN_START = performance.now();
  let msgCount = 0;

  milestones.query_call = performance.now();
  ts(`run${run}: query() called`);

  try {
    const queryOpts = {
      prompt: PROMPT,
      options: {
        cwd: '/workspace/group',
        maxTurns: 1,
        permissionMode: 'bypassPermissions',
        allowDangerouslySkipPermissions: true,
        allowedTools: USE_TOOLS ? ['Bash', 'Read', 'Glob', 'Grep'] : [],
        disallowedTools: ['WebSearch', 'WebFetch'],
        env: { ...process.env },
      }
    };

    for await (const message of query(queryOpts)) {
      const now = performance.now();
      const elapsed = ((now - RUN_START) / 1000).toFixed(1);
      msgCount++;

      const msgType = message.type === 'system'
        ? `system/${message.subtype || '?'}`
        : message.type;

      messages.push({
        seq: msgCount,
        type: msgType,
        elapsed_s: parseFloat(elapsed),
      });

      // Track milestones
      if (message.type === 'system' && !milestones.first_system) {
        milestones.first_system = now;
        ts(`run${run}: first_system (${msgType})`);
      }
      if (message.type === 'system' && message.subtype === 'init') {
        milestones.session_init = now;
        const sid = message.session_id || '?';
        ts(`run${run}: session_init (id=${sid.slice(0,12)}...)`);
      }
      if (message.type === 'assistant' && !milestones.first_assistant) {
        milestones.first_assistant = now;
        // Extract text content
        let text = '';
        if (message.message?.content) {
          for (const block of message.message.content) {
            if (block.type === 'text') text += block.text;
          }
        }
        ts(`run${run}: first_assistant TTFB (${text.length} chars: "${text.slice(0,50)}")`);
      }
      if (message.type === 'result') {
        milestones.result = now;
        const resultText = message.result || '';
        ts(`run${run}: result (${resultText.length} chars: "${resultText.slice(0,80)}")`);
      }

      // Log every message for detailed trace
      if (msgCount <= 30) {
        console.error(`  [msg#${msgCount}] +${elapsed}s ${msgType}${
          message.type === 'system' && message.subtype === 'init' ? ` session=${(message.session_id||'').slice(0,12)}` : ''
        }`);
      }
    }
  } catch (err) {
    ts(`run${run}: ERROR: ${err.message}`);
    milestones.error = err.message;
  }

  milestones.complete = performance.now();
  ts(`run${run}: complete (${msgCount} messages total)`);

  // Compute breakdown
  const breakdown = {};
  const ref = milestones.query_call;

  breakdown.total_s = parseFloat(((milestones.complete - ref) / 1000).toFixed(1));

  if (milestones.first_system) {
    breakdown.to_first_system_s = parseFloat(((milestones.first_system - ref) / 1000).toFixed(1));
  }
  if (milestones.session_init) {
    breakdown.to_session_init_s = parseFloat(((milestones.session_init - ref) / 1000).toFixed(1));
  }
  if (milestones.first_assistant) {
    breakdown.to_first_assistant_s = parseFloat(((milestones.first_assistant - ref) / 1000).toFixed(1));
    breakdown.api_ttfb_s = milestones.session_init
      ? parseFloat(((milestones.first_assistant - milestones.session_init) / 1000).toFixed(1))
      : null;
  }
  if (milestones.result) {
    breakdown.to_result_s = parseFloat(((milestones.result - ref) / 1000).toFixed(1));
    breakdown.streaming_s = milestones.first_assistant
      ? parseFloat(((milestones.result - milestones.first_assistant) / 1000).toFixed(1))
      : null;
  }
  if (milestones.result && milestones.complete) {
    breakdown.post_result_s = parseFloat(((milestones.complete - milestones.result) / 1000).toFixed(1));
  }

  console.error(`\n[BREAKDOWN run${run}]`);
  for (const [k, v] of Object.entries(breakdown)) {
    console.error(`  ${k.padEnd(25)} ${v}s`);
  }

  allRuns.push({ run, breakdown, messages, error: milestones.error || null });
}

// Final summary
console.error(`\n${'═'.repeat(60)}`);
console.error(`AGGREGATE SUMMARY (${RUNS} runs)`);
console.error(`${'═'.repeat(60)}`);

const fields = ['to_first_system_s', 'to_session_init_s', 'to_first_assistant_s', 'api_ttfb_s', 'streaming_s', 'to_result_s', 'post_result_s', 'total_s'];
for (const field of fields) {
  const vals = allRuns.map(r => r.breakdown[field]).filter(v => v != null);
  if (vals.length === 0) continue;
  const avg = (vals.reduce((a,b) => a+b, 0) / vals.length).toFixed(1);
  const mn = Math.min(...vals).toFixed(1);
  const mx = Math.max(...vals).toFixed(1);
  console.error(`  ${field.padEnd(25)} avg=${avg}s  min=${mn}s  max=${mx}s`);
}

// Module import time (one-time)
console.error(`  ${'module_import_s'.padEnd(25)} ${((T_IMPORT_END - T_IMPORT_START)/1000).toFixed(1)}s (one-time)`);

// Output JSON
console.log(JSON.stringify({ benchmark: 'container-sdk-substep', timestamp: new Date().toISOString(), module_import_s: parseFloat(((T_IMPORT_END - T_IMPORT_START)/1000).toFixed(1)), runs: allRuns }, null, 2));
