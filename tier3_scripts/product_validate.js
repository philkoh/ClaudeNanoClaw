const https = require('https');

// Call Pangolinfo API for a single ASIN
function lookupAsin(apiKey, asin, zipCode) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify({
      url: `https://www.amazon.com/dp/${asin}`,
      zipcode: zipCode || undefined,
    });

    const options = {
      hostname: 'api.pangolinfo.com',
      port: 443,
      path: '/v1/scrape',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'Content-Length': Buffer.byteLength(payload),
      },
      timeout: 15000,
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          resolve(json);
        } catch (e) {
          reject(new Error(`Invalid JSON from Pangolinfo: ${body.slice(0, 200)}`));
        }
      });
    });

    req.on('error', (e) => reject(e));
    req.on('timeout', () => { req.destroy(); reject(new Error('Pangolinfo request timeout')); });
    req.end(payload);
  });
}

// Extract product data from Pangolinfo response
function parseProduct(json) {
  // Pangolinfo wraps results in data.json[0].data.results[0] or similar
  // Handle multiple possible response structures
  const data = json?.data?.json?.[0]?.data?.results?.[0]
    || json?.data?.results?.[0]
    || json?.data
    || json;

  return {
    asin: data.asin || 'N/A',
    title: data.title || 'Unknown',
    price: data.price || 'N/A',
    deliveryTime: data.deliveryTime || data.delivery_time || 'N/A',
    seller: data.seller || 'N/A',
    shipper: data.shipper || 'N/A',
    star: data.star || data.rating_star || 'N/A',
    rating: data.rating || data.reviews_total || 'N/A',
    brand: data.brand || '',
    availability: data.availability || (data.in_stock ? 'In Stock' : ''),
  };
}

async function main() {
  const asinList = process.env.ASIN_LIST;
  if (!asinList) {
    console.error('ERROR: ASIN_LIST env var required (comma-separated)');
    process.exit(1);
  }

  const apiKey = process.env.PANGOLINFO_API_KEY;
  if (!apiKey) {
    console.error('ERROR: PANGOLINFO_API_KEY env var required');
    process.exit(1);
  }

  const zipCode = process.env.ZIP_CODE || '';
  const asins = asinList.split(',').map(s => s.trim()).filter(Boolean).slice(0, 5);

  const startTime = Date.now();
  let output = '';
  let successCount = 0;
  let errorCount = 0;

  for (let i = 0; i < asins.length; i++) {
    const asin = asins[i];
    try {
      const response = await lookupAsin(apiKey, asin, zipCode);
      const p = parseProduct(response);
      successCount++;

      output += `${i + 1}. ${p.title} — ${p.price}\n`;
      output += `   ASIN: ${p.asin} | Seller: ${p.seller} | Ships: ${p.shipper}\n`;
      output += `   Delivery: ${p.deliveryTime}`;
      if (p.availability) output += ` | ${p.availability}`;
      output += '\n';
      output += `   Rating: ${p.star} stars (${p.rating} reviews)`;
      if (p.brand) output += ` | Brand: ${p.brand}`;
      output += '\n\n';
    } catch (e) {
      errorCount++;
      output += `${i + 1}. ASIN ${asin} — ERROR: ${e.message}\n\n`;
    }
  }

  const elapsed = Date.now() - startTime;
  console.error(`[pangolinfo-usage] ${JSON.stringify({
    asins_requested: asins.length,
    success: successCount,
    errors: errorCount,
    duration_ms: elapsed,
    zip_code: zipCode || 'none',
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
