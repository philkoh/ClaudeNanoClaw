const { ImapFlow } = require("imapflow");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { simpleParser } = require("mailparser");

async function fetchRecentEmails(count = 10, timing) {
  const client = new ImapFlow({
    host: "imap.gmail.com",
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
  timing.connectMs = Date.now() - t0;

  const lock = await client.getMailboxLock("INBOX");
  const emails = [];

  try {
    const status = await client.status("INBOX", { messages: true });
    const startSeq = Math.max(1, status.messages - count + 1);

    const t1 = Date.now();
    for await (const msg of client.fetch(
      { seq: `${startSeq}:*` },
      { envelope: true, source: true }
    )) {
      const parsed = await simpleParser(msg.source);
      emails.push({
        date: msg.envelope.date?.toISOString(),
        from: msg.envelope.from?.map(a => `${a.name || ""} <${a.address}>`).join(", "),
        subject: msg.envelope.subject || "(no subject)",
        body: (parsed.text || parsed.html || "").slice(0, 2000),
      });
    }
    timing.fetchMs = Date.now() - t1;
  } finally {
    lock.release();
  }

  await client.logout();
  return emails;
}

async function summarizeEmails(emails, timing) {
  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

  const emailList = emails
    .map(
      (e, i) =>
        `--- Email ${i + 1} ---\nDate: ${e.date}\nFrom: ${e.from}\nSubject: ${e.subject}\nBody:\n${e.body}\n`
    )
    .join("\n");

  const prompt = `You are an executive assistant summarizing emails for a busy executive.

Summarize the following ${emails.length} emails into a concise briefing. For each email:
- One line with sender, subject, and key action/info
- Flag anything that needs urgent attention

End with a "Needs Action" section listing items requiring a response.

Emails:
${emailList}`;

  const t2 = Date.now();
  const result = await model.generateContent(prompt);
  const usage = result.response.usageMetadata;
  if (usage) {
    console.error(`[gemini-usage] ${JSON.stringify({prompt_tokens:usage.promptTokenCount||0,completion_tokens:usage.candidatesTokenCount||0,total_tokens:usage.totalTokenCount||0})}`);
  }
  timing.geminiMs = Date.now() - t2;

  let text = result.response.text();

  // Server-side output cap: max 500 chars per email summary (plan Section 6.3)
  const MAX_CHARS_PER_EMAIL = 500;
  const maxOutput = emails.length * MAX_CHARS_PER_EMAIL + 500; // +500 for headers/footer
  if (text.length > maxOutput) {
    text = text.slice(0, maxOutput) + "\n\n[OUTPUT TRUNCATED — exceeded safety cap]";
  }
  return text;
}

async function main() {
  const totalStart = Date.now();
  const timing = {};
  const count = parseInt(process.env.EMAIL_COUNT || "10", 10);
  console.log(`Fetching up to ${count} recent emails...`);

  const emails = await fetchRecentEmails(count, timing);
  console.log(`Found ${emails.length} emails. Summarizing with Gemini...\n`);

  if (emails.length === 0) {
    console.log("No emails to summarize.");
    return;
  }

  const summary = await summarizeEmails(emails, timing);
  console.log("=== EMAIL BRIEFING ===\n");
  console.log(summary);
  console.log("\n=== END BRIEFING ===");

  const totalMs = Date.now() - totalStart;
  console.error(`[email-triage] imap_connect=${timing.connectMs}ms imap_fetch=${timing.fetchMs}ms gemini=${timing.geminiMs}ms total=${totalMs}ms emails=${emails.length}`);
}

main().catch(e => {
  console.error("ERROR:", e.message);
  process.exit(1);
});
