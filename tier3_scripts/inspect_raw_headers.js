// Dump raw headers from one marketing email to verify List-Unsubscribe presence
const { ImapFlow } = require('imapflow');

async function dumpRawHeaders() {
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

  await client.connect();
  const lock = await client.getMailboxLock('INBOX');

  try {
    // Search for a known bulk sender
    const hits = await client.search({ from: 'papajohns' });
    if (hits.length === 0) {
      console.log('No papajohns emails found, trying costco...');
      const hits2 = await client.search({ from: 'costco' });
      if (hits2.length === 0) {
        console.log('No bulk sender emails found');
        return;
      }
      hits.push(...hits2);
    }

    const uid = hits[hits.length - 1]; // most recent
    for await (const msg of client.fetch([uid], { source: true })) {
      const raw = msg.source.toString('utf-8');
      // Extract just the headers (everything before first blank line)
      const headerEnd = raw.indexOf('\r\n\r\n');
      const headers = headerEnd > 0 ? raw.slice(0, headerEnd) : raw.slice(0, 5000);

      // Print all headers, highlight anything with "unsubscribe" or "list-"
      const lines = headers.split(/\r?\n/);
      for (const line of lines) {
        const lower = line.toLowerCase();
        if (lower.includes('unsubscribe') || lower.includes('list-') || lower.includes('forward') || lower.includes('delivered-to') || lower.includes('x-forwarded')) {
          console.log(`>>> ${line}`);
        }
      }
      console.log('\n--- FULL HEADER BLOCK (first 3000 chars) ---');
      console.log(headers.slice(0, 3000));
    }
  } finally {
    lock.release();
  }

  await client.logout();
}

dumpRawHeaders().catch(e => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
