const { ImapFlow } = require('imapflow');
const { simpleParser } = require('mailparser');
const https = require('https');
const http = require('http');
const { URL } = require('url');

function fetchImage(url, timeoutMs = 3000) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => { try { req.destroy(); } catch(e) {} resolve(null); }, timeoutMs);
    const proto = url.startsWith('https') ? https : http;
    const req = proto.get(url, { timeout: timeoutMs }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        // Follow one redirect
        return fetchImage(res.headers.location, timeoutMs).then(resolve);
      }
      if (res.statusCode !== 200) {
        resolve(null);
        return;
      }
      const contentType = res.headers['content-type'] || '';
      if (!contentType.startsWith('image/')) {
        resolve(null);
        return;
      }
      const chunks = [];
      let size = 0;
      res.on('data', (chunk) => {
        size += chunk.length;
        if (size > 5 * 1024 * 1024) { res.destroy(); resolve(null); return; }
        chunks.push(chunk);
      });
      res.on('end', () => {
        clearTimeout(timer);
        const buf = Buffer.concat(chunks);
        if (buf.length < 500) { resolve(null); return; } // skip tiny tracking pixels
        resolve({ mimeType: contentType.split(';')[0], data: buf.toString('base64'), size: buf.length });
      });
      res.on('error', () => { clearTimeout(timer); resolve(null); });
    });
    req.on('error', () => { clearTimeout(timer); resolve(null); });
    req.on('timeout', () => { clearTimeout(timer); req.destroy(); resolve(null); });
  });
}

async function downloadRemoteImages(html, maxImages = 10) {
  const imgRegex = /<img[^>]+src=["']?(https?:\/\/[^"'\s>]+)["']?/gi;
  const urls = [];
  let match;
  while ((match = imgRegex.exec(html)) !== null && urls.length < maxImages * 3) {
    urls.push(match[1]);
  }
  // Deduplicate
  const unique = [...new Set(urls)].slice(0, maxImages);
  const results = await Promise.all(unique.map(u => fetchImage(u)));
  return results.filter(Boolean);
}

async function searchEmails(query, maxResults = 3) {
  const client = new ImapFlow({
    host: 'imap.gmail.com',
    port: 993,
    secure: true,
    auth: {
      user: process.env.GMAIL_IMAP_USER,
      pass: process.env.GMAIL_IMAP_APP_PASSWORD,
    },
    logger: false,
  });

  const t0 = Date.now();
  await client.connect();
  const tConnect = Date.now();

  const lock = await client.getMailboxLock('INBOX');
  const results = [];

  try {
    const subjectHits = await client.search({ subject: query });
    const fromHits = await client.search({ from: query });
    const uniqueUids = [...new Set([...subjectHits, ...fromHits])];
    const uids = uniqueUids.slice(-maxResults);

    const tSearch = Date.now();

    if (uids.length > 0) {
      for await (const msg of client.fetch(uids, {
        envelope: true,
        source: true,
      })) {
        const parsed = await simpleParser(msg.source);
        const body = (parsed.text || '').slice(0, 8000) ||
                     (parsed.html || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').slice(0, 8000) ||
                     '(no readable body)';

        // Collect inline images and attachments (for --interpret mode)
        const images = [];
        if (parsed.attachments) {
          for (const att of parsed.attachments) {
            if (att.contentType && att.contentType.startsWith('image/') && att.content) {
              images.push({
                mimeType: att.contentType,
                data: att.content.toString('base64'),
                filename: att.filename || 'image',
                size: att.size || att.content.length,
              });
            }
          }
        }

        results.push({
          date: msg.envelope.date?.toISOString(),
          from: msg.envelope.from?.map(a => `${a.name || ''} <${a.address}>`).join(', '),
          subject: msg.envelope.subject || '(no subject)',
          body,
          html: parsed.html || '',
          images,
        });
      }
    }

    const tFetch = Date.now();
    console.error(`[email-detail] imap_connect=${tConnect - t0}ms imap_search=${tSearch - tConnect}ms imap_fetch=${tFetch - tSearch}ms total=${tFetch - t0}ms matches=${results.length}`);
  } finally {
    lock.release();
  }

  await client.logout();
  return results;
}

async function interpretWithGemini(emails, prompt) {
  const { GoogleGenerativeAI } = require('@google/generative-ai');
  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

  const parts = [];
  let totalImages = 0;

  // Add the instruction
  parts.push({
    text: `You are extracting specific information from email content. Answer the following question based on the email(s) provided. Be concise and direct.\n\nQuestion: ${prompt}\n\n`,
  });

  for (let i = 0; i < emails.length; i++) {
    const e = emails[i];
    parts.push({
      text: `--- Email ${i + 1} ---\nDate: ${e.date}\nFrom: ${e.from}\nSubject: ${e.subject}\nBody:\n${e.body}\n`,
    });

    // Include HTML — strip tags to reduce token count but preserve text content
    if (e.html.length > 0) {
      const cleanHtml = e.html.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
                              .replace(/<[^>]+>/g, ' ')
                              .replace(/&nbsp;/g, ' ')
                              .replace(/\s+/g, ' ')
                              .trim();
      parts.push({
        text: `Cleaned email text (from HTML):\n${cleanHtml.slice(0, 30000)}\n`,
      });
    }

    // Include inline/attached images
    for (const img of e.images) {
      if (img.size > 5 * 1024 * 1024) continue;
      parts.push({
        inlineData: { mimeType: img.mimeType, data: img.data },
      });
      parts.push({ text: `[Attached image: ${img.filename}]\n` });
      totalImages++;
    }

    // Download and include remote images from HTML
    if (e.html) {
      const tDl = Date.now();
      const remoteImages = await downloadRemoteImages(e.html, 10);
      const tDlDone = Date.now();
      console.error(`[email-detail] remote_images: downloaded=${remoteImages.length} in ${tDlDone - tDl}ms`);
      for (const img of remoteImages) {
        parts.push({
          inlineData: { mimeType: img.mimeType, data: img.data },
        });
        parts.push({ text: `[Remote image from email]\n` });
        totalImages++;
      }
    }
  }

  const tGemini = Date.now();
  const result = await model.generateContent({ contents: [{ parts }] });
  const usage = result.response.usageMetadata;
  if (usage) {
    console.error(`[gemini-usage] ${JSON.stringify({prompt_tokens:usage.promptTokenCount||0,completion_tokens:usage.candidatesTokenCount||0,total_tokens:usage.totalTokenCount||0})}`);
  }
  let text = result.response.text();
  const tDone = Date.now();

  console.error(`[email-detail] gemini=${tDone - tGemini}ms images_sent=${totalImages}`);

  // Output cap: 3000 chars
  if (text.length > 3000) {
    text = text.slice(0, 3000) + '\n\n[OUTPUT TRUNCATED]';
  }
  return text;
}

async function main() {
  const query = process.env.EMAIL_QUERY;
  if (!query) {
    console.log('ERROR: EMAIL_QUERY environment variable is required');
    process.exit(1);
  }
  const maxResults = parseInt(process.env.EMAIL_MAX_RESULTS || '3', 10);
  const interpretPrompt = process.env.EMAIL_INTERPRET || '';

  console.log(`Searching emails matching: "${query}" (max ${maxResults})...`);
  const results = await searchEmails(query, maxResults);

  if (results.length === 0) {
    console.log(`No emails found matching "${query}".`);
    return;
  }

  console.log(`Found ${results.length} matching email(s).\n`);

  if (interpretPrompt) {
    // Gemini interpretation mode
    const imageCount = results.reduce((n, e) => n + e.images.length, 0);
    console.log(`Interpreting with Gemini (${imageCount} image(s))...\n`);
    const answer = await interpretWithGemini(results, interpretPrompt);
    console.log('=== INTERPRETATION ===\n');
    console.log(answer);
    console.log('\n=== END INTERPRETATION ===');
  } else {
    // Raw body mode (no Gemini)
    for (let i = 0; i < results.length; i++) {
      const e = results[i];
      console.log(`=== Email ${i + 1} of ${results.length} ===`);
      console.log(`Date: ${e.date}`);
      console.log(`From: ${e.from}`);
      console.log(`Subject: ${e.subject}`);
      if (e.images.length > 0) {
        console.log(`Images: ${e.images.length} (use --interpret to analyze)`);
      }
      console.log(`\n${e.body}`);
      console.log(`\n=== End Email ${i + 1} ===\n`);
    }
  }
}

main().catch(e => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
