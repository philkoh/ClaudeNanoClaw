const { ImapFlow } = require('imapflow');

async function main() {
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
  console.log('IMAP connected to Gmail');

  const lock = await client.getMailboxLock('INBOX');
  try {
    const status = await client.status('INBOX', { messages: true, unseen: true });
    console.log(`INBOX: ${status.messages} total, ${status.unseen} unseen`);

    // Fetch the 5 most recent messages (headers only)
    const messages = [];
    for await (const msg of client.fetch(
      { seq: `${Math.max(1, status.messages - 4)}:*` },
      { envelope: true }
    )) {
      messages.push({
        seq: msg.seq,
        date: msg.envelope.date?.toISOString(),
        from: msg.envelope.from?.map(a => `${a.name || ''} <${a.address}>`).join(', '),
        subject: msg.envelope.subject,
      });
    }

    console.log('\nLatest messages:');
    for (const m of messages) {
      console.log(`  [${m.seq}] ${m.date} | From: ${m.from} | Subject: ${m.subject}`);
    }
  } finally {
    lock.release();
  }

  await client.logout();
  console.log('\nIMAP test complete.');
}

main().catch(e => {
  console.error('IMAP ERROR:', e.message);
  process.exit(1);
});
