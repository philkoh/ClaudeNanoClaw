// describe_image.js — Describe an image using Gemini vision
// Usage: GEMINI_API_KEY=... IMAGE_BASE64=... [IMAGE_PROMPT="..."] node describe_image.js
// Or pipe base64 via stdin: echo "<base64>" | GEMINI_API_KEY=... node describe_image.js
// IMAGE_PROMPT defaults to a general description prompt
const { GoogleGenerativeAI } = require('@google/generative-ai');

async function main() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) { console.error('ERROR: GEMINI_API_KEY required'); process.exit(1); }

  let imageBase64 = process.env.IMAGE_BASE64 || '';
  if (!imageBase64) {
    const chunks = [];
    for await (const chunk of process.stdin) chunks.push(chunk);
    imageBase64 = Buffer.concat(chunks).toString('utf8').trim();
  }
  if (!imageBase64) { console.error('ERROR: No image data'); process.exit(1); }

  const prompt = process.env.IMAGE_PROMPT ||
    'Describe this image in detail. If it contains text, lists, or handwriting, transcribe all text exactly. If it contains a receipt or document, extract all key information. Be thorough but concise.';

  const mimeType = process.env.IMAGE_MIME || 'image/jpeg';

  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' }, { apiVersion: 'v1beta' });

  const result = await model.generateContent({
    contents: [{
      role: 'user',
      parts: [
        { inlineData: { mimeType, data: imageBase64 } },
        { text: prompt },
      ],
    }],
  });

  const usage = result.response.usageMetadata;
  if (usage) {
    console.error(`[gemini-usage] ${JSON.stringify({prompt_tokens:usage.promptTokenCount||0,completion_tokens:usage.candidatesTokenCount||0,total_tokens:usage.totalTokenCount||0})}`);
  }

  const MAX_OUTPUT = 3000;
  let text = result.response.text();
  if (text.length > MAX_OUTPUT) {
    text = text.slice(0, MAX_OUTPUT) + '\n\n[OUTPUT TRUNCATED]';
  }
  console.log(text);
}

main().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
