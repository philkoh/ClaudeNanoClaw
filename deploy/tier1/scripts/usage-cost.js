#!/usr/bin/env node
// usage-cost.js — Calculate API costs from usage JSONL files
// Usage: node usage-cost.js <anthropic-file> <gemini-file> <start-date>
const fs = require('fs');

// Anthropic pricing per 1M tokens (as of March 2026)
const ANTHROPIC_PRICING = {
  'claude-sonnet-4-6':            { input: 3.00, output: 15.00, cache_read: 0.30, cache_create: 3.75 },
  'claude-sonnet-4-5-20250514':   { input: 3.00, output: 15.00, cache_read: 0.30, cache_create: 3.75 },
  'claude-haiku-4-5-20251001':    { input: 0.80, output: 4.00,  cache_read: 0.08, cache_create: 1.00 },
  'claude-opus-4-6':              { input: 15.00, output: 75.00, cache_read: 1.50, cache_create: 18.75 },
  '_default':                     { input: 3.00, output: 15.00, cache_read: 0.30, cache_create: 3.75 },
};

// Gemini pricing per 1M tokens
const GEMINI_PRICING = { prompt: 0.15, completion: 0.60 };

const anthropicFile = process.argv[2];
const geminiFile = process.argv[3];
const startDate = process.argv[4];
const cutoff = new Date(startDate).getTime();

// --- Anthropic ---
console.log('--- Anthropic (Proxy Tracking) ---');
if (anthropicFile && fs.existsSync(anthropicFile)) {
  const lines = fs.readFileSync(anthropicFile, 'utf8').trim().split('\n').filter(Boolean);
  let total_input = 0, total_output = 0, total_cache_read = 0, total_cache_create = 0, requests = 0;
  const byModel = {};

  for (const line of lines) {
    try {
      const r = JSON.parse(line);
      if (new Date(r.ts).getTime() < cutoff) continue;
      requests++;
      total_input += r.input_tokens || 0;
      total_output += r.output_tokens || 0;
      total_cache_read += r.cache_read_input_tokens || 0;
      total_cache_create += r.cache_creation_input_tokens || 0;
      const m = r.model || 'unknown';
      if (!byModel[m]) byModel[m] = { input: 0, output: 0, cache_read: 0, cache_create: 0, requests: 0 };
      byModel[m].input += r.input_tokens || 0;
      byModel[m].output += r.output_tokens || 0;
      byModel[m].cache_read += r.cache_read_input_tokens || 0;
      byModel[m].cache_create += r.cache_creation_input_tokens || 0;
      byModel[m].requests++;
    } catch (e) {}
  }

  function cost(model, inp, out, cr, cc) {
    const p = ANTHROPIC_PRICING[model] || ANTHROPIC_PRICING['_default'];
    return (inp * p.input + out * p.output + cr * p.cache_read + cc * p.cache_create) / 1e6;
  }

  const totalCost = cost('_default', total_input, total_output, total_cache_read, total_cache_create);
  const dp = ANTHROPIC_PRICING['_default'];

  // Cache hit rate
  let cacheHits = 0, cacheMisses = 0;
  for (const line of lines) {
    try {
      const r = JSON.parse(line);
      if (new Date(r.ts).getTime() < cutoff) continue;
      if (r.cache_read_input_tokens > 0) cacheHits++;
      if (r.cache_creation_input_tokens > 1000) cacheMisses++;
    } catch {}
  }
  const hitRate = requests > 0 ? Math.round((cacheHits / requests) * 100) : 0;

  console.log('Requests: ' + requests);
  console.log('Cache hit rate: ' + hitRate + '% (' + cacheHits + '/' + requests + ' calls were cache reads)');
  console.log('Cold starts: ' + cacheMisses);
  console.log('Input tokens: ' + total_input.toLocaleString());
  console.log('Output tokens: ' + total_output.toLocaleString());
  console.log('Cache read tokens: ' + total_cache_read.toLocaleString());
  console.log('Cache creation tokens: ' + total_cache_create.toLocaleString());
  console.log('Total tokens: ' + (total_input + total_output + total_cache_read + total_cache_create).toLocaleString());
  console.log('');
  console.log('Estimated cost: $' + totalCost.toFixed(2));
  console.log('  input=$' + (total_input * dp.input / 1e6).toFixed(3)
    + '  output=$' + (total_output * dp.output / 1e6).toFixed(3)
    + '  cache_read=$' + (total_cache_read * dp.cache_read / 1e6).toFixed(3)
    + '  cache_create=$' + (total_cache_create * dp.cache_create / 1e6).toFixed(3));
  console.log('');

  for (const [m, d] of Object.entries(byModel)) {
    const mCost = cost(m, d.input, d.output, d.cache_read, d.cache_create);
    console.log('  ' + m + ': ' + d.requests + ' reqs, $' + mCost.toFixed(2)
      + ' -- ' + d.input.toLocaleString() + ' in, ' + d.output.toLocaleString() + ' out, '
      + d.cache_read.toLocaleString() + ' cache_read, ' + d.cache_create.toLocaleString() + ' cache_create');
  }
} else {
  console.log('(no proxy usage data yet)');
}

console.log('');

// --- Gemini ---
console.log('--- Gemini (Dispatch Tracking) ---');
if (geminiFile && fs.existsSync(geminiFile)) {
  const lines = fs.readFileSync(geminiFile, 'utf8').trim().split('\n').filter(Boolean);
  let total_prompt = 0, total_completion = 0, requests = 0;
  const byScript = {};

  for (const line of lines) {
    try {
      const r = JSON.parse(line);
      if (new Date(r.ts).getTime() < cutoff) continue;
      requests++;
      total_prompt += r.prompt_tokens || 0;
      total_completion += r.completion_tokens || 0;
      const s = r.script || 'unknown';
      if (!byScript[s]) byScript[s] = { prompt: 0, completion: 0, requests: 0 };
      byScript[s].prompt += r.prompt_tokens || 0;
      byScript[s].completion += r.completion_tokens || 0;
      byScript[s].requests++;
    } catch (e) {}
  }

  const geminiCost = (total_prompt * GEMINI_PRICING.prompt + total_completion * GEMINI_PRICING.completion) / 1e6;

  console.log('Requests: ' + requests);
  console.log('Prompt tokens: ' + total_prompt.toLocaleString());
  console.log('Completion tokens: ' + total_completion.toLocaleString());
  console.log('Total tokens: ' + (total_prompt + total_completion).toLocaleString());
  console.log('Estimated cost: $' + geminiCost.toFixed(4));
  console.log('');

  for (const [s, d] of Object.entries(byScript)) {
    const sCost = (d.prompt * GEMINI_PRICING.prompt + d.completion * GEMINI_PRICING.completion) / 1e6;
    console.log('  ' + s + ': ' + d.requests + ' reqs, $' + sCost.toFixed(4)
      + ' -- ' + d.prompt.toLocaleString() + ' prompt, ' + d.completion.toLocaleString() + ' completion');
  }
} else {
  console.log('(no Gemini dispatch usage data yet)');
}

// --- Combined total ---
console.log('');
let anthropicTotal = 0, geminiTotal = 0;
if (anthropicFile && fs.existsSync(anthropicFile)) {
  const lines = fs.readFileSync(anthropicFile, 'utf8').trim().split('\n').filter(Boolean);
  let ti = 0, to = 0, tcr = 0, tcc = 0;
  for (const l of lines) {
    try {
      const r = JSON.parse(l);
      if (new Date(r.ts).getTime() < cutoff) continue;
      ti += r.input_tokens || 0; to += r.output_tokens || 0;
      tcr += r.cache_read_input_tokens || 0; tcc += r.cache_creation_input_tokens || 0;
    } catch (e) {}
  }
  const dp = ANTHROPIC_PRICING['_default'];
  anthropicTotal = (ti * dp.input + to * dp.output + tcr * dp.cache_read + tcc * dp.cache_create) / 1e6;
}
if (geminiFile && fs.existsSync(geminiFile)) {
  const lines = fs.readFileSync(geminiFile, 'utf8').trim().split('\n').filter(Boolean);
  let tp = 0, tc = 0;
  for (const l of lines) {
    try {
      const r = JSON.parse(l);
      if (new Date(r.ts).getTime() < cutoff) continue;
      tp += r.prompt_tokens || 0; tc += r.completion_tokens || 0;
    } catch (e) {}
  }
  geminiTotal = (tp * GEMINI_PRICING.prompt + tc * GEMINI_PRICING.completion) / 1e6;
}
console.log('--- Combined ---');
console.log('Anthropic: $' + anthropicTotal.toFixed(2) + '  Gemini: $' + geminiTotal.toFixed(4) + '  Total: $' + (anthropicTotal + geminiTotal).toFixed(2));
