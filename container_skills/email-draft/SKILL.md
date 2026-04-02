---
name: email-draft
description: Create email drafts in phil@emtera.com's Exchange mailbox. Use when user asks to draft, compose, or write an email. The draft appears in Outlook Drafts — user reviews and sends manually.
---

# /draft — Create Exchange Email Draft

Creates a draft email in phil@emtera.com's Exchange/Outlook mailbox via Microsoft Graph API. The draft is NOT sent — it goes to the Drafts folder for manual review and send.

## Usage

The dispatch script accepts a **base64-encoded JSON payload** as a single argument.

### Step 1: Build the JSON payload

```json
{
  "to": "recipient@example.com",
  "subject": "Subject line here",
  "body": "<p>HTML body content here</p>",
  "cc": "optional@example.com",
  "importance": "normal"
}
```

Required fields: `to`, `subject`, `body`
Optional fields: `cc`, `importance` (normal/high/low, default: normal)

- `to` and `cc` accept comma-separated addresses for multiple recipients
- `body` is HTML — use `<p>`, `<br>`, `<b>`, `<ul>/<li>` etc. for formatting
- For plain text, just wrap in `<p>` tags

### Step 2: Base64-encode and dispatch

```bash
PAYLOAD=$(echo -n '{"to":"recipient@example.com","subject":"Meeting tomorrow","body":"<p>Hi, are we still on for 3pm?</p>"}' | base64 -w 0)
ssh -F /workspace/extra/agent-ssh/config host.docker.internal "bash /home/ubuntu/dispatch/create-draft.sh $PAYLOAD"
```

**Important:** Use `base64 -w 0` (no line wrapping) so the payload is a single continuous string.

### Step 3: Confirm to user

On success, the script returns:
```
SUCCESS: Draft created in phil@emtera.com Drafts folder
Subject: Meeting tomorrow
To: recipient@example.com
Draft ID: AAMk...
```

Tell the user the draft has been created and they can review/send it from Outlook.

## Examples

| User says... | Action |
|---|---|
| "Draft an email to john@acme.com about the invoice" | Build JSON with to/subject/body, encode, dispatch |
| "Write a reply to Sarah about the meeting" | Ask for Sarah's email if unknown, then create draft |
| "Compose a follow-up email" | Ask who it's to and what to say, then create draft |
| "Email the team about the outage" | Ask for team email addresses, compose body, create draft |

## Composing good drafts

When the user asks you to draft an email:

1. **Infer context** — Use conversation history and any relevant email lookups to understand the context
2. **Professional tone** — Unless told otherwise, write in a professional but friendly tone matching Phil's style
3. **HTML formatting** — Use proper HTML: `<p>` for paragraphs, `<br>` for line breaks, `<b>` for emphasis
4. **Signature** — Do NOT add a signature (Outlook handles that)
5. **Confirm before sending** — Always show the user what you're about to draft (to, subject, body summary) and get confirmation before dispatching

## Security notes

- This creates a DRAFT only — it cannot send email
- The Graph API credentials are in Tier 1 vault (never exposed to the container)
- Draft goes to phil@emtera.com's Drafts folder only
- Never put sensitive information in drafts without user confirmation
- This skill has NO read access to the mailbox — use `/email` (email-triage skill) for reading
