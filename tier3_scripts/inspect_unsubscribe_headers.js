// Inspect recent emails for List-Unsubscribe headers and unsubscribe links
// to determine what survives forwarding

const { ImapFlow } = require('imapflow');
const { simpleParser } = require('mailparser');

async function inspectHeaders(count = 15) {
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
    const status = await client.status('INBOX', { messages: true });
    const startSeq = Math.max(1, status.messages - count + 1);

    let idx = 0;
    for await (const msg of client.fetch(
      { seq: `${startSeq}:*` },
      { envelope: true, source: true, headers: true }
    )) {
      idx++;
      const parsed = await simpleParser(msg.source);
      const headers = parsed.headers;

      const from = msg.envelope.from?.map(a => `${a.name || ''} <${a.address}>`).join(', ') || '?';
      const subject = msg.envelope.subject || '(no subject)';
      const date = msg.envelope.date?.toISOString() || '?';

      // Extract key headers
      const listUnsub = headers.get('list-unsubscribe') || null;
      const listUnsubPost = headers.get('list-unsubscribe-post') || null;
      const xForwardedTo = headers.get('x-forwarded-to') || null;
      const xForwardedFor = headers.get('x-forwarded-for') || null;
      const deliveredTo = headers.get('delivered-to') || null;
      const receivedSpf = headers.get('received-spf') || null;
      const xOriginalTo = headers.get('x-original-to') || null;

      // Look for unsubscribe links in body
      let bodyUnsubLinks = [];
      const html = parsed.html || '';
      const unsubRegex = /href=["']?(https?:\/\/[^"'\s>]*unsub[^"'\s>]*)["']?/gi;
      let match;
      while ((match = unsubRegex.exec(html)) !== null) {
        bodyUnsubLinks.push(match[1].slice(0, 120));
      }
      // Also check for "unsubscribe" anchor text links
      const anchorRegex = /<a[^>]+href=["']?(https?:\/\/[^"'\s>]+)["']?[^>]*>[^<]*unsub[^<]*/gi;
      while ((match = anchorRegex.exec(html)) !== null) {
        if (!bodyUnsubLinks.includes(match[1].slice(0, 120))) {
          bodyUnsubLinks.push(match[1].slice(0, 120));
        }
      }
      bodyUnsubLinks = bodyUnsubLinks.slice(0, 3);

      console.log(`\n=== Email ${idx} ===`);
      console.log(`Date: ${date}`);
      console.log(`From: ${from}`);
      console.log(`Subject: ${subject}`);
      console.log(`Delivered-To: ${deliveredTo || '(none)'}`);
      console.log(`X-Forwarded-To: ${xForwardedTo || '(none)'}`);
      console.log(`X-Forwarded-For: ${xForwardedFor || '(none)'}`);
      console.log(`List-Unsubscribe: ${listUnsub || '(NONE)'}`);
      console.log(`List-Unsubscribe-Post: ${listUnsubPost || '(NONE)'}`);
      if (bodyUnsubLinks.length > 0) {
        console.log(`Body unsub links: ${bodyUnsubLinks.join(' | ')}`);
      } else {
        console.log(`Body unsub links: (none found)`);
      }
    }
  } finally {
    lock.release();
  }

  await client.logout();
}

inspectHeaders().catch(e => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
