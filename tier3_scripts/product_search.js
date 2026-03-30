const { GoogleGenerativeAI } = require('@google/generative-ai');
const https = require('https');
const http = require('http');

// Extract ASIN from an Amazon URL
// Patterns: /dp/B0XXXXXXXXX, /gp/product/B0XXXXXXXXX, /ASIN/B0XXXXXXXXX
function extractAsin(url) {
  const match = url.match(/\/(?:dp|gp\/product|ASIN)\/([A-Z0-9]{10})(?:[\/?\s]|$)/i);
  return match ? match[1].toUpperCase() : null;
}

// Follow redirects to resolve a shortened/tracking URL (up to 5 hops)
function resolveUrl(url, maxRedirects = 5) {
  return new Promise((resolve) => {
    if (maxRedirects <= 0) { resolve(url); return; }
    const client = url.startsWith('https') ? https : http;
    const req = client.request(url, { method: 'HEAD', timeout: 3000 }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        let next = res.headers.location;
        if (next.startsWith('/')) {
          const parsed = new URL(url);
          next = `${parsed.protocol}//${parsed.host}${next}`;
        }
        resolve(resolveUrl(next, maxRedirects - 1));
      } else {
        resolve(url);
      }
    });
    req.on('error', () => resolve(url));
    req.on('timeout', () => { req.destroy(); resolve(url); });
    req.end();
  });
}

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
        parts: [{
          text: `What are the Amazon ASINs and current prices for: ${query}

Search for this product. I need the Amazon ASIN (a 10-character alphanumeric code like B0DYTF8L2W that appears in Amazon URLs after /dp/). Check Amazon product listings, review sites, and shopping comparison sites that reference the Amazon ASIN.

List up to 5 results:
1. [Product Title]
   Price: $[price] | ASIN: [code] | Stock: [status]`
        }],
      },
    ],
    tools: [{ googleSearch: {} }],
  });

  const usage = result.response.usageMetadata;
  if (usage) {
    console.error(`[gemini-usage] ${JSON.stringify({prompt_tokens:usage.promptTokenCount||0,completion_tokens:usage.candidatesTokenCount||0,total_tokens:usage.totalTokenCount||0})}`);
  }

  const response = result.response;
  const metadata = response.candidates?.[0]?.groundingMetadata;

  // Strategy 1: Extract ASINs from grounding chunk URLs (direct Amazon links)
  const asinSet = new Set();
  if (metadata?.groundingChunks) {
    for (const chunk of metadata.groundingChunks) {
      if (!chunk.web?.uri) continue;
      const uri = chunk.web.uri;

      // Check direct Amazon URLs
      let asin = extractAsin(uri);

      // If URL is a Google redirect, try resolving it
      if (!asin && uri.includes('grounding-api-redirect')) {
        const resolved = await resolveUrl(uri);
        asin = extractAsin(resolved);
      }

      if (asin) asinSet.add(asin);
    }
  }

  // Strategy 2: Extract ASINs from the text response itself
  // Gemini may include ASINs in its formatted response (we asked it to)
  let text = response.text();
  const textAsinMatches = text.matchAll(/ASIN:\s*([A-Z0-9]{10})/gi);
  for (const match of textAsinMatches) {
    const asin = match[1].toUpperCase();
    if (asin !== 'UNKNOWN') asinSet.add(asin);
  }

  // Also look for Amazon URL patterns in the text
  const urlAsinMatches = text.matchAll(/amazon\.com\/(?:.*?\/)?(?:dp|gp\/product)\/([A-Z0-9]{10})/gi);
  for (const match of urlAsinMatches) {
    asinSet.add(match[1].toUpperCase());
  }

  // Build output: Gemini's summary + consolidated ASIN list
  const MAX_OUTPUT = 4000;
  let output = '';

  if (text.length > 3000) {
    text = text.slice(0, 3000) + '\n[TRUNCATED]';
  }
  output += text;

  // Append consolidated ASIN list for follow-up validation
  const asins = [...asinSet];
  if (asins.length > 0) {
    output += `\n\n--- ASINs Found (${asins.length}) ---`;
    output += `\n  ${asins.join(', ')}`;
  } else {
    output += '\n\n--- No ASINs found. Try searching with a more specific product name or model number. ---';
  }

  if (output.length > MAX_OUTPUT) {
    output = output.slice(0, MAX_OUTPUT) + '\n[OUTPUT TRUNCATED]';
  }

  console.log(output);
}

main().catch(e => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
