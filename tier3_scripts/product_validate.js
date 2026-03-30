const https = require('https');

// Call RapidAPI Real-Time Amazon Data for a single ASIN
// Docs: https://rapidapi.com/letscrape-6bRBa3QguO5/api/real-time-amazon-data
function lookupAsin(apiKey, asin) {
  return new Promise((resolve, reject) => {
    const params = new URLSearchParams({
      asin: asin,
      country: 'US',
    });

    const options = {
      hostname: 'real-time-amazon-data.p.rapidapi.com',
      path: `/product-details?${params}`,
      method: 'GET',
      headers: {
        'X-RapidAPI-Key': apiKey,
        'X-RapidAPI-Host': 'real-time-amazon-data.p.rapidapi.com',
      },
      timeout: 20000,
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          if (json.status === 'ERROR') {
            reject(new Error(json.error?.message || `API error (HTTP ${res.statusCode})`));
            return;
          }
          resolve(json);
        } catch (e) {
          reject(new Error(`Invalid JSON from RapidAPI: ${body.slice(0, 200)}`));
        }
      });
    });

    req.on('error', (e) => reject(e));
    req.on('timeout', function() { this.destroy(); reject(new Error('RapidAPI request timeout')); });
    req.end();
  });
}

// Extract product data from Real-Time Amazon Data response
function parseProduct(json) {
  const d = json?.data || {};

  return {
    asin: d.asin || 'N/A',
    title: d.product_title || 'Unknown',
    price: d.product_price || 'N/A',
    originalPrice: d.product_original_price || null,
    delivery: d.delivery || 'N/A',
    availability: d.product_availability || 'Unknown',
    rating: d.product_star_rating || 'N/A',
    ratingsTotal: d.product_num_ratings || 0,
    isPrime: d.is_prime || false,
    brand: d.product_byline || d.brand || '',
    salesVolume: d.sales_volume || '',
    numOffers: d.product_num_offers || 0,
    isBestSeller: d.is_best_seller || false,
    isAmazonChoice: d.is_amazon_choice || false,
  };
}

async function main() {
  const asinList = process.env.ASIN_LIST;
  if (!asinList) {
    console.error('ERROR: ASIN_LIST env var required (comma-separated)');
    process.exit(1);
  }

  const apiKey = process.env.RAPIDAPI_KEY;
  if (!apiKey) {
    console.error('ERROR: RAPIDAPI_KEY env var required');
    process.exit(1);
  }

  const asins = asinList.split(',').map(s => s.trim()).filter(Boolean).slice(0, 5);

  const startTime = Date.now();
  let output = '';
  let successCount = 0;
  let errorCount = 0;

  for (let i = 0; i < asins.length; i++) {
    const asin = asins[i];
    try {
      const response = await lookupAsin(apiKey, asin);
      const p = parseProduct(response);
      successCount++;

      output += `${i + 1}. ${p.title} — ${p.price}`;
      if (p.originalPrice && p.originalPrice !== p.price) {
        output += ` (was ${p.originalPrice})`;
      }
      output += '\n';
      output += `   ASIN: ${p.asin}`;
      if (p.isPrime) output += ' | Prime';
      if (p.isBestSeller) output += ' | Best Seller';
      if (p.isAmazonChoice) output += ' | Amazon Choice';
      output += '\n';
      output += `   Delivery: ${p.delivery} | ${p.availability}\n`;
      output += `   Rating: ${p.rating}/5 (${Number(p.ratingsTotal).toLocaleString()} reviews)`;
      if (p.brand) output += ` | ${p.brand}`;
      output += '\n';
      if (p.salesVolume) output += `   ${p.salesVolume}\n`;
      if (p.numOffers > 1) output += `   ${p.numOffers} offers available\n`;
      output += '\n';
    } catch (e) {
      errorCount++;
      output += `${i + 1}. ASIN ${asin} — ERROR: ${e.message}\n\n`;
    }
  }

  const elapsed = Date.now() - startTime;
  console.error(`[rapidapi-usage] ${JSON.stringify({
    asins_requested: asins.length,
    success: successCount,
    errors: errorCount,
    duration_ms: elapsed,
  })}`);

  // Cap output
  const MAX_OUTPUT = 4000;
  if (output.length > MAX_OUTPUT) {
    output = output.slice(0, MAX_OUTPUT) + '\n[OUTPUT TRUNCATED]';
  }

  console.log(output.trimEnd());
}

main().catch(e => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
