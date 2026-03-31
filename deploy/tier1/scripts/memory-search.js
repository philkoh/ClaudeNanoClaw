#!/usr/bin/env node
// memory-search.js — Hybrid vector + BM25 search over memory index
// Usage: GEMINI_API_KEY=... node memory-search.js <db-path> "<query>" [limit]
// Returns JSON array of ranked results
const Database = require('better-sqlite3');
const { execSync } = require('child_process');

const VECTOR_WEIGHT = 0.7;
const BM25_WEIGHT = 0.3;

function blobToEmbedding(blob) {
  const buf = Buffer.from(blob);
  const floats = new Float32Array(buf.length / 4);
  for (let i = 0; i < floats.length; i++) {
    floats[i] = buf.readFloatLE(i * 4);
  }
  return floats;
}

function cosineSimilarity(a, b) {
  let dot = 0, normA = 0, normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (Math.sqrt(normA) * Math.sqrt(normB) + 1e-8);
}

function getQueryEmbedding(query, geminiKey) {
  const tmpFile = '/tmp/embed_query.json';
  try {
    require('fs').writeFileSync(tmpFile, JSON.stringify([query]));
    const result = execSync(
      `cat ${tmpFile} | ssh tier3 "GEMINI_API_KEY='${geminiKey}' EMBED_TASK_TYPE='RETRIEVAL_QUERY' NODE_PATH=/usr/lib/node_modules node /home/ubuntu/scripts/embed_text.js"`,
      { encoding: 'utf8', timeout: 30000 }
    );
    require('fs').unlinkSync(tmpFile);
    const embeddings = JSON.parse(result.trim());
    return new Float32Array(embeddings[0]);
  } catch (e) {
    try { require('fs').unlinkSync(tmpFile); } catch {}
    console.error('Query embedding failed:', e.message);
    return null;
  }
}

function main() {
  const dbPath = process.argv[2];
  const query = process.argv[3];
  const limit = parseInt(process.argv[4] || '10');

  if (!dbPath || !query) {
    console.error('Usage: node memory-search.js <db-path> "<query>" [limit]');
    process.exit(1);
  }

  const geminiKey = process.env.GEMINI_API_KEY;
  if (!geminiKey) { console.error('ERROR: GEMINI_API_KEY required'); process.exit(1); }

  const db = new Database(dbPath, { readonly: true });

  // 1. Vector search: embed query, compute cosine similarity
  const queryEmb = getQueryEmbedding(query, geminiKey);
  const allChunks = db.prepare('SELECT id, source, start_line, end_line, content, embedding FROM chunks').all();

  const vectorScores = new Map();
  if (queryEmb) {
    for (const chunk of allChunks) {
      if (!chunk.embedding) continue;
      const chunkEmb = blobToEmbedding(chunk.embedding);
      const sim = cosineSimilarity(queryEmb, chunkEmb);
      vectorScores.set(chunk.id, sim);
    }
  }

  // Normalize vector scores to [0, 1]
  let maxVec = 0, minVec = 1;
  for (const s of vectorScores.values()) {
    if (s > maxVec) maxVec = s;
    if (s < minVec) minVec = s;
  }
  const vecRange = maxVec - minVec || 1;
  for (const [id, s] of vectorScores) {
    vectorScores.set(id, (s - minVec) / vecRange);
  }

  // 2. BM25 keyword search via FTS5
  const bm25Scores = new Map();
  try {
    const ftsResults = db.prepare(
      `SELECT rowid, rank FROM chunks_fts WHERE chunks_fts MATCH ? ORDER BY rank LIMIT 50`
    ).all(query.replace(/[^\w\s]/g, ' '));

    // FTS5 rank is negative (lower = better), normalize to [0, 1]
    if (ftsResults.length > 0) {
      const minRank = ftsResults[ftsResults.length - 1].rank;
      const maxRank = ftsResults[0].rank;
      const range = maxRank - minRank || 1;
      for (const r of ftsResults) {
        bm25Scores.set(r.rowid, 1 - (r.rank - minRank) / range);
      }
    }
  } catch (e) {
    // FTS query might fail on special chars, fall back to vector only
  }

  // 3. Hybrid scoring
  const allIds = new Set([...vectorScores.keys(), ...bm25Scores.keys()]);
  const results = [];
  for (const id of allIds) {
    const vecScore = vectorScores.get(id) || 0;
    const bm25Score = bm25Scores.get(id) || 0;
    const hybridScore = VECTOR_WEIGHT * vecScore + BM25_WEIGHT * bm25Score;
    if (hybridScore < 0.15) continue; // min threshold
    results.push({ id, score: hybridScore, vecScore, bm25Score });
  }

  results.sort((a, b) => b.score - a.score);
  const topResults = results.slice(0, limit);

  // 4. Fetch full chunk data
  const output = [];
  for (const r of topResults) {
    const chunk = allChunks.find(c => c.id === r.id);
    if (!chunk) continue;
    output.push({
      source: chunk.source,
      startLine: chunk.start_line,
      endLine: chunk.end_line,
      content: chunk.content,
      score: Math.round(r.score * 1000) / 1000,
      vectorScore: Math.round(r.vecScore * 1000) / 1000,
      bm25Score: Math.round(r.bm25Score * 1000) / 1000,
    });
  }

  db.close();
  console.log(JSON.stringify(output, null, 2));
}

main();
