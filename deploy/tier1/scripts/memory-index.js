#!/usr/bin/env node
// memory-index.js — Index markdown files into SQLite with Gemini embeddings
// Usage: GEMINI_API_KEY=... node memory-index.js <memory-dir> <db-path>
// Chunks markdown files, gets embeddings from Tier 3, stores in SQLite with FTS5
const Database = require('better-sqlite3');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const CHUNK_SIZE = 384;    // tokens (~1500 chars)
const CHUNK_OVERLAP = 64;  // tokens (~250 chars)
const CHARS_PER_TOKEN = 4; // rough estimate

function chunkText(text, source) {
  const chunkChars = CHUNK_SIZE * CHARS_PER_TOKEN;
  const overlapChars = CHUNK_OVERLAP * CHARS_PER_TOKEN;
  const chunks = [];
  const lines = text.split('\n');
  let current = '';
  let lineNum = 1;
  let chunkStartLine = 1;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    // Split on headers or when chunk is large enough
    const isHeader = /^#{1,3}\s/.test(line);
    if (isHeader && current.length > 200) {
      chunks.push({ text: current.trim(), source, startLine: chunkStartLine, endLine: lineNum - 1 });
      // Keep overlap from end of previous chunk
      const overlapStart = Math.max(0, current.length - overlapChars);
      current = current.slice(overlapStart) + '\n' + line + '\n';
      chunkStartLine = Math.max(1, lineNum - current.split('\n').length + 1);
    } else if (current.length >= chunkChars) {
      chunks.push({ text: current.trim(), source, startLine: chunkStartLine, endLine: lineNum - 1 });
      const overlapStart = Math.max(0, current.length - overlapChars);
      current = current.slice(overlapStart) + '\n' + line + '\n';
      chunkStartLine = Math.max(1, lineNum - current.split('\n').length + 1);
    } else {
      current += line + '\n';
    }
    lineNum++;
  }
  if (current.trim()) {
    chunks.push({ text: current.trim(), source, startLine: chunkStartLine, endLine: lineNum - 1 });
  }
  return chunks;
}

function getEmbeddings(texts, geminiKey) {
  // Call Tier 3 via SSH for embeddings, in batches of 20 to avoid E2BIG
  const BATCH_SIZE = 20;
  const allEmbeddings = [];

  for (let i = 0; i < texts.length; i += BATCH_SIZE) {
    const batch = texts.slice(i, i + BATCH_SIZE);
    const input = JSON.stringify(batch);
    const tmpFile = `/tmp/embed_batch_${i}.json`;

    try {
      // Write batch to temp file, then pipe via stdin to avoid shell arg limits
      require('fs').writeFileSync(tmpFile, input);
      const result = execSync(
        `cat ${tmpFile} | ssh tier3 "GEMINI_API_KEY='${geminiKey}' EMBED_TASK_TYPE='RETRIEVAL_DOCUMENT' NODE_PATH=/usr/lib/node_modules node /home/ubuntu/scripts/embed_text.js"`,
        { encoding: 'utf8', timeout: 60000, maxBuffer: 50 * 1024 * 1024 }
      );
      const batchEmbeddings = JSON.parse(result.trim());
      allEmbeddings.push(...batchEmbeddings);
      require('fs').unlinkSync(tmpFile);
      console.log(`  Embedded batch ${Math.floor(i/BATCH_SIZE)+1}/${Math.ceil(texts.length/BATCH_SIZE)} (${batch.length} chunks)`);
    } catch (e) {
      console.error(`Batch ${i} embedding failed:`, e.message);
      try { require('fs').unlinkSync(tmpFile); } catch {}
      return null;
    }
  }

  return allEmbeddings;
}

function embeddingToBlob(embedding) {
  const buf = Buffer.alloc(embedding.length * 4);
  for (let i = 0; i < embedding.length; i++) {
    buf.writeFloatLE(embedding[i], i * 4);
  }
  return buf;
}

function main() {
  const memoryDir = process.argv[2];
  const dbPath = process.argv[3];
  if (!memoryDir || !dbPath) {
    console.error('Usage: node memory-index.js <memory-dir> <db-path>');
    console.error('  memory-dir: directory containing .md files to index');
    console.error('  db-path: path to SQLite database');
    process.exit(1);
  }

  const geminiKey = process.env.GEMINI_API_KEY;
  if (!geminiKey) { console.error('ERROR: GEMINI_API_KEY required'); process.exit(1); }

  // Find all .md files
  const mdFiles = [];
  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.md') && entry.name !== 'CLAUDE.md' && entry.name !== 'HEARTBEAT.md') {
        mdFiles.push(full);
      }
    }
  }
  walk(memoryDir);

  console.log(`Found ${mdFiles.length} markdown files to index`);

  // Chunk all files
  const allChunks = [];
  for (const file of mdFiles) {
    const content = fs.readFileSync(file, 'utf8').trim();
    if (!content) continue;
    const relPath = path.relative(memoryDir, file);
    const chunks = chunkText(content, relPath);
    allChunks.push(...chunks);
  }

  console.log(`Created ${allChunks.length} chunks`);
  if (allChunks.length === 0) {
    console.log('No chunks to index');
    return;
  }

  // Compute content hash to check if re-indexing is needed
  const contentHash = crypto.createHash('md5')
    .update(allChunks.map(c => c.text).join('\n'))
    .digest('hex');

  // Init database
  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');

  db.exec(`
    CREATE TABLE IF NOT EXISTS chunks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source TEXT NOT NULL,
      start_line INTEGER,
      end_line INTEGER,
      content TEXT NOT NULL,
      embedding BLOB,
      created_at TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS meta (
      key TEXT PRIMARY KEY,
      value TEXT
    );
  `);

  // Check if already indexed with same content
  const existingHash = db.prepare('SELECT value FROM meta WHERE key = ?').get('content_hash');
  if (existingHash && existingHash.value === contentHash) {
    console.log('Content unchanged, skipping re-index');
    db.close();
    return;
  }

  // Create FTS5 virtual table
  db.exec(`DROP TABLE IF EXISTS chunks_fts`);
  db.exec(`
    CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
      content, source, content=chunks, content_rowid=id
    );
  `);

  // Clear existing data
  db.exec('DELETE FROM chunks');
  db.exec('DELETE FROM chunks_fts');

  // Get embeddings in batch
  const texts = allChunks.map(c => c.text);
  console.log(`Getting embeddings for ${texts.length} chunks via Tier 3...`);
  const embeddings = getEmbeddings(texts, geminiKey);

  if (!embeddings || embeddings.length !== texts.length) {
    console.error(`ERROR: Expected ${texts.length} embeddings, got ${embeddings ? embeddings.length : 0}`);
    db.close();
    process.exit(1);
  }

  // Insert chunks with embeddings
  const insertChunk = db.prepare(
    'INSERT INTO chunks (source, start_line, end_line, content, embedding) VALUES (?, ?, ?, ?, ?)'
  );
  const insertFts = db.prepare(
    'INSERT INTO chunks_fts (rowid, content, source) VALUES (?, ?, ?)'
  );

  const insertAll = db.transaction(() => {
    for (let i = 0; i < allChunks.length; i++) {
      const chunk = allChunks[i];
      const embBlob = embeddingToBlob(embeddings[i]);
      const info = insertChunk.run(chunk.source, chunk.startLine, chunk.endLine, chunk.text, embBlob);
      insertFts.run(info.lastInsertRowid, chunk.text, chunk.source);
    }
    db.prepare('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)').run('content_hash', contentHash);
    db.prepare('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)').run('embedding_dim', String(embeddings[0].length));
    db.prepare('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)').run('indexed_at', new Date().toISOString());
    db.prepare('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)').run('chunk_count', String(allChunks.length));
  });

  insertAll();
  console.log(`Indexed ${allChunks.length} chunks with ${embeddings[0].length}-dim embeddings`);
  db.close();
}

main();
