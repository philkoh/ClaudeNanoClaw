const { ImapFlow } = require('imapflow');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const { simpleParser } = require('mailparser');

async function fetchRecentEmails(count = 10) {
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
  const emails = [];

  try {
    const status = await client.status('INBOX', { messages: true });
    const startSeq = Math.max(1, status.messages - count + 1);

    for await (const msg of client.fetch(
      { seq: `${startSeq}:*` },
      { envelope: true, source: true }
    )) {
      const parsed = await simpleParser(msg.source);
      emails.push({
        date: msg.envelope.date?.toISOString(),
        from: msg.envelope.from?.map(a => `${a.name || ''} <${a.address}>`).join(', '),
        subject: msg.envelope.subject || '(no subject)',
        body: (parsed.text || parsed.html || '').slice(0, 2000),
      });
    }
  } finally {
    lock.release();
  }

  await client.logout();
  return emails;
}

async function summarizeEmails(emails) {
  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

  const emailList = emails
    .map(
      (e, i) =>
        `--- Email ${i + 1} ---\nDate: ${e.date}\nFrom: ${e.from}\nSubject: ${e.subject}\nBody:\n${e.body}\n`
    )
    .join('\n');

  const prompt = `You are an executive assistant summarizing emails for a busy executive.

Summarize the following ${emails.length} emails into a concise briefing. For each email:
- One line with sender, subject, and key action/info
- Flag anything that needs urgent attention

End with a "Needs Action" section listing items requiring a response.

Emails:
${emailList}`;

  const result = await model.generateContent(prompt);
  let text = result.response.text();

  // Server-side output cap: max 500 chars per email summary (plan Section 6.3)
  const MAX_CHARS_PER_EMAIL = 500;
  const maxOutput = emails.length * MAX_CHARS_PER_EMAIL + 500; // +500 for headers/footer
  if (text.length > maxOutput) {
    text = text.slice(0, maxOutput) + '\n\n[OUTPUT TRUNCATED — exceeded safety cap]';
  }
  return text;
}

async function main() {
  const count = parseInt(process.env.EMAIL_COUNT || '10', 10);
  console.log(`Fetching up to ${count} recent emails...`);

  const emails = await fetchRecentEmails(count);
  console.log(`Found ${emails.length} emails. Summarizing with Gemini...\n`);

  if (emails.length === 0) {
    console.log('No emails to summarize.');
    return;
  }

  const summary = await summarizeEmails(emails);
  console.log('=== EMAIL BRIEFING ===\n');
  console.log(summary);
  console.log('\n=== END BRIEFING ===');
}

main().catch(e => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
