const https = require('https');

// Call Rainforest API for a single ASIN
// Docs: https://docs.trajectdata.com/rainforestapi/product-data-api/overview
function lookupAsin(apiKey, asin) {
  return new Promise((resolve, reject) => {
    const params = new URLSearchParams({
      api_key: apiKey,
      type: 'product',
      asin: asin,
      amazon_domain: 'amazon.com',
    });

    const url = `https://api.rainforestapi.com/request?${params}`;

    https.get(url, { timeout: 20000 }, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          if (json.request_info?.success === false) {
            reject(new Error(json.request_info?.message || `API error (HTTP ${res.statusCode})`));
            return;
          }
          resolve(json);
        } catch (e) {
          reject(new Error(`Invalid JSON from Rainforest: ${body.slice(0, 200)}`));
        }
      });
    }).on('error', (e) => reject(e))
      .on('timeout', function() { this.destroy(); reject(new Error('Rainforest API request timeout')); });
  });
}

// Extract product data from Rainforest API response
function parseProduct(json) {
  const p = json?.product || {};
  const bb = p.buybox_winner || {};
  const price = bb.price || {};
  const avail = bb.availability || {};
  const fulfill = bb.fulfillment || {};
  const delivery = fulfill.standard_delivery || {};
  const seller = bb.fulfillment?.third_party_seller || {};

  // Build seller string
  let sellerName = 'Amazon.com';
  if (seller.name) {
    sellerName = seller.name;
  } else if (fulfill.is_sold_by_amazon) {
    sellerName = 'Amazon.com';
  }

  // Build shipper string
  let shipperName = 'Unknown';
  if (fulfill.is_fulfilled_by_amazon) {
    shipperName = 'Amazon (FBA)';
  } else if (fulfill.is_fulfilled_by_third_party) {
    shipperName = sellerName;
  } else if (fulfill.is_sold_by_amazon) {
    shipperName = 'Amazon';
  }

  return {
    asin: p.asin || 'N/A',
    title: p.title || 'Unknown',
    price: price.raw || (price.value ? `$${price.value}` : 'N/A'),
    deliveryDate: delivery.date || 'N/A',
    deliveryName: delivery.name || '',
    availability: avail.raw || avail.type || 'Unknown',
    dispatchDays: avail.dispatch_days || '',
    seller: sellerName,
    shipper: shipperName,
    rating: p.rating || 'N/A',
    ratingsTotal: p.ratings_total || 0,
    brand: p.brand || '',
  };
}

async function main() {
  const asinList = process.env.ASIN_LIST;
  if (!asinList) {
    console.error('ERROR: ASIN_LIST env var required (comma-separated)');
    process.exit(1);
  }

  const apiKey = process.env.RAINFOREST_API_KEY;
  if (!apiKey) {
    console.error('ERROR: RAINFOREST_API_KEY env var required');
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

      output += `${i + 1}. ${p.title} — ${p.price}\n`;
      output += `   ASIN: ${p.asin} | Seller: ${p.seller} | Ships: ${p.shipper}\n`;
      output += `   Delivery: ${p.deliveryDate}`;
      if (p.deliveryName) output += ` (${p.deliveryName})`;
      output += ` | ${p.availability}`;
      output += '\n';
      output += `   Rating: ${p.rating}/5 (${p.ratingsTotal.toLocaleString()} reviews)`;
      if (p.brand) output += ` | Brand: ${p.brand}`;
      output += '\n\n';
    } catch (e) {
      errorCount++;
      output += `${i + 1}. ASIN ${asin} — ERROR: ${e.message}\n\n`;
    }
  }

  const elapsed = Date.now() - startTime;
  console.error(`[rainforest-usage] ${JSON.stringify({
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
