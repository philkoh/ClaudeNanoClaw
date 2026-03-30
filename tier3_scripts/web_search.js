const { GoogleGenerativeAI } = require('@google/generative-ai');

async function main() {
  const query = process.env.SEARCH_QUERY;
  if (!query) {
    console.error('ERROR: SEARCH_QUERY env var required');
    process.exit(1);
  }

  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel(
    { model: 'gemini-2.5-flash' },
    { apiVersion: 'v1beta' }
  );

  const result = await model.generateContent({
    contents: [
      {
        role: 'user',
        parts: [{ text: query }],
      },
    ],
    tools: [{ googleSearch: {} }],
  });

  const usage = result.response.usageMetadata;
  if (usage) {
    console.error(`[gemini-usage] ${JSON.stringify({prompt_tokens:usage.promptTokenCount||0,completion_tokens:usage.candidatesTokenCount||0,total_tokens:usage.totalTokenCount||0})}`);
  }

  const response = result.response;

  // Server-side output cap: max 3000 chars for search results (plan Section 6.3)
  const MAX_SEARCH_OUTPUT = 3000;
  let text = response.text();
  if (text.length > MAX_SEARCH_OUTPUT) {
    text = text.slice(0, MAX_SEARCH_OUTPUT) + '\n\n[OUTPUT TRUNCATED — exceeded safety cap]';
  }
  console.log(text);

  const metadata = response.candidates?.[0]?.groundingMetadata;
  if (metadata?.groundingChunks) {
    console.log('\n--- Sources ---');
    for (const chunk of metadata.groundingChunks) {
      if (chunk.web) {
        console.log(`  ${chunk.web.title}: ${chunk.web.uri}`);
      }
    }
  }
}

main().catch(e => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
