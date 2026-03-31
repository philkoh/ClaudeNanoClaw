// embed_text.js — Generate embeddings via Gemini text-embedding-004
// Usage: GEMINI_API_KEY=... EMBED_TEXT="hello world" node embed_text.js
// Input: EMBED_TEXT env var (single text) or stdin (JSON array of texts for batch)
// Output: JSON array of embedding vectors
const { GoogleGenerativeAI } = require('@google/generative-ai');

async function main() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) { console.error('ERROR: GEMINI_API_KEY required'); process.exit(1); }

  const taskType = process.env.EMBED_TASK_TYPE || 'RETRIEVAL_DOCUMENT';
  let texts = [];

  if (process.env.EMBED_TEXT) {
    texts = [process.env.EMBED_TEXT];
  } else {
    // Read JSON array from stdin
    const chunks = [];
    for await (const chunk of process.stdin) chunks.push(chunk);
    const input = Buffer.concat(chunks).toString('utf8').trim();
    if (!input) { console.error('ERROR: No input'); process.exit(1); }
    texts = JSON.parse(input);
    if (!Array.isArray(texts)) texts = [texts];
  }

  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: 'gemini-embedding-001' });

  const results = [];
  // Batch in groups of 100 (Gemini limit)
  for (let i = 0; i < texts.length; i += 100) {
    const batch = texts.slice(i, i + 100);
    const batchResult = await model.batchEmbedContents({
      requests: batch.map(text => ({
        content: { parts: [{ text }] },
        taskType,
      })),
    });
    for (const emb of batchResult.embeddings) {
      results.push(emb.values);
    }
  }

  console.log(JSON.stringify(results));
}

main().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
