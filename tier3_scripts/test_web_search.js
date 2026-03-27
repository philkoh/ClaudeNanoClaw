const { GoogleGenerativeAI } = require('@google/generative-ai');

async function main() {
  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel(
    { model: 'gemini-2.5-flash' },
    { apiVersion: 'v1beta' }
  );

  const result = await model.generateContent({
    contents: [
      {
        role: 'user',
        parts: [{ text: 'What are the top 3 tech news stories today? Be concise.' }],
      },
    ],
    tools: [{ googleSearch: {} }],
  });

  const response = result.response;
  console.log('=== GROUNDED WEB SEARCH TEST ===\n');
  console.log(response.text());

  // Show grounding metadata if available
  const metadata = response.candidates?.[0]?.groundingMetadata;
  if (metadata) {
    console.log('\n--- Grounding Sources ---');
    if (metadata.groundingChunks) {
      for (const chunk of metadata.groundingChunks) {
        if (chunk.web) {
          console.log(`  ${chunk.web.title}: ${chunk.web.uri}`);
        }
      }
    }
    if (metadata.searchEntryPoint?.renderedContent) {
      console.log('\n(Search entry point available)');
    }
  } else {
    console.log('\n(No grounding metadata returned)');
  }

  console.log('\n=== END TEST ===');
}

main().catch(e => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
