# NanoClaw Three-Tier System: Credential Setup Guide

**Last updated:** 2026-03-23

This guide walks you through obtaining every API key, app password, and credential needed for the three-tier system, and how to enter them as environment variables for Claude Code to store in the vault.

---

## Table of Contents

1. [Gemini API Key (Tier 3)](#1-gemini-api-key-tier-3)
2. [Gmail App Password for IMAP Read-Only (Tier 3)](#2-gmail-app-password-for-imap-read-only-tier-3)
3. [Exchange Email: Forward to Gmail (Tier 3)](#3-exchange-email-forward-to-gmail-tier-3)
4. [Setting Environment Variables for Claude Code](#4-setting-environment-variables-for-claude-code)
5. [Quick Reference: All Environment Variables](#5-quick-reference-all-environment-variables)

---

## 1. Gemini API Key (Tier 3)

Tier 3 uses Google's Gemini API with native web search grounding for research and email summarization. The free tier includes 1,500 grounded search requests/day.

### Steps

1. Open your browser and go to **[aistudio.google.com](https://aistudio.google.com)**

2. **Sign in** with your Google account (the same one you use for Gmail is fine, or a separate one)

3. If this is your first visit, accept the **Terms of Service** when prompted

4. In the **left sidebar**, click **"Get API key"**
   - If you don't see it in the sidebar, look for a key icon, or go directly to [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)

5. Click the **"Create API key"** button

6. If prompted to select a Google Cloud project:
   - Select the auto-created default project, OR
   - Click **"Create API key in new project"** (Google creates one for you automatically)

7. Your API key will be displayed. **Copy it immediately** and save it somewhere secure (e.g., a password manager)
   - The key looks like: `AIzaSyD-xxxxxxxxxxxxxxxxxxxxxxxxxxxx` (39 characters)
   - You can view it again later in Google AI Studio, but copy it now

8. **Optional but recommended:** Restrict the key
   - Click the key name to open settings
   - Under "API restrictions," select **"Restrict key"**
   - Select only **"Generative Language API"**
   - Click **Save**

### Set the environment variable

```bash
export GEMINI_API_KEY='AIzaSyD-your-actual-key-here'
```

### Sources
- [Google AI Studio API Key page](https://aistudio.google.com/app/apikey)
- [Using Gemini API Keys (official docs)](https://ai.google.dev/gemini-api/docs/api-key)
- [Gemini API Quickstart](https://ai.google.dev/gemini-api/docs/quickstart)

---

## 2. Gmail App Password for IMAP Read-Only (Tier 3)

Tier 3 reads your Gmail inbox via IMAP using an app-specific password. Since Exchange email is forwarded to Gmail (see Section 3), this single IMAP connection covers ALL your email. This requires 2-Step Verification to be enabled on your Google account.

> **Note:** Google retired "Less Secure Apps" in May 2025. App passwords are now the only way to use IMAP with third-party apps.

### Step 2a: Enable 2-Step Verification (skip if already enabled)

1. Go to **[myaccount.google.com](https://myaccount.google.com)**

2. In the left sidebar, click **"Security"**

3. Scroll down to **"How you sign in to Google"**

4. Click **"2-Step Verification"**

5. If it says "Off," click **"Get started"**

6. Follow the prompts:
   - Enter your password when asked
   - Choose a verification method (Google prompts on your phone, authenticator app, or SMS)
   - Complete the setup and click **"Turn on"**

7. You should now see "2-Step Verification: On" on the Security page

### Step 2b: Enable IMAP in Gmail (usually on by default since Jan 2025)

1. Go to **[mail.google.com](https://mail.google.com)**

2. Click the **gear icon** (top-right) -> **"See all settings"**

3. Click the **"Forwarding and POP/IMAP"** tab

4. Under "IMAP access," make sure **"Enable IMAP"** is selected

5. Click **"Save Changes"** at the bottom

### Step 2c: Generate an App Password

1. Go to **[myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)**
   - If you get a "page not found" error, make sure 2-Step Verification is turned on (Step 2a)
   - If you have a Workspace account, your admin must allow app passwords

2. You'll see an **"App name"** field. Type a descriptive name:
   ```
   NanoClaw-Tier3-IMAP
   ```

3. Click **"Create"**

4. A 16-character password will be displayed in a yellow box, formatted as four groups of four letters:
   ```
   abcd efgh ijkl mnop
   ```

5. **Copy this password** (remove the spaces when using it). You will NOT be able to see it again after closing the dialog.

6. Click **"Done"**

### Set the environment variable

```bash
export GMAIL_IMAP_APP_PASSWORD='abcdefghijklmnop'
```

Also set your Gmail address:

```bash
export GMAIL_IMAP_USER='philkoh.admin@gmail.com'
```

### IMAP Connection Details (for reference)

| Setting | Value |
|---------|-------|
| Server | imap.gmail.com |
| Port | 993 |
| Encryption | SSL/TLS |
| Username | Your full Gmail address |
| Password | The 16-char app password |

### Sources
- [Sign in with app passwords (Google Support)](https://support.google.com/accounts/answer/185833?hl=en)
- [Gmail IMAP setup guide](https://www.getmailbird.com/setup/access-gmail-com-via-imap-smtp)
- [How to Create a Gmail App Password (2026)](https://www.mailjerry.com/create-gmail-app-password)

---

## 3. Exchange Email: Forward to Gmail (Tier 3)

Instead of setting up complex OAuth 2.0 / Microsoft Graph API integration (Microsoft killed basic auth and app passwords for IMAP in 2024-2026), we simply forward all Exchange email to Gmail. Tier 3 then reads everything from one inbox.

**Benefits:**
- No Azure app registration, client secrets, or refresh tokens
- No Microsoft auth headaches
- One IMAP connection covers all email (personal Gmail + work Exchange)
- Forwarded emails preserve original sender in headers
- Slight delay (usually seconds) on forwarding

### Step 3a: Set Up Forwarding in Outlook Web App (OWA)

1. Go to **[outlook.office.com](https://outlook.office.com)** and sign in with your Exchange account (phil@emtera.com)

2. Click the **gear icon** (top-right) -> **"View all Outlook settings"**
   - Or go directly to: **Settings** -> **Mail** -> **Forwarding**

3. In the left sidebar, navigate to: **Mail** -> **Forwarding**

4. Check **"Enable forwarding"**

5. In the **"Forward my email to"** field, enter:
   ```
   philkoh.admin@gmail.com
   ```

6. **Check "Keep a copy of forwarded messages"** — this ensures you can still read email in Outlook directly if needed

7. Click **"Save"**

### Step 3b: Verify Forwarding Works

1. Send a test email to **phil@emtera.com** from any other account

2. Check **philkoh.admin@gmail.com** — the email should appear within a few seconds to a minute

3. Verify the original sender shows correctly in the Gmail message headers

### Step 3c: Create a Gmail Filter (optional but recommended)

To keep forwarded Exchange emails organized in Gmail:

1. In Gmail, click the **search bar** at the top

2. Click the **filter icon** (right side of search bar) or click **"Show search options"**

3. In the **"To"** field, enter: `phil@emtera.com`

4. Click **"Create filter"**

5. Check **"Apply the label:"** and create a new label called **"Exchange/Emtera"**

6. Optionally check **"Also apply filter to matching conversations"**

7. Click **"Create filter"**

Now all forwarded Exchange emails will be automatically labeled in Gmail, making it easy for Tier 3 to distinguish between personal Gmail and work Exchange messages.

### No environment variables needed

Forwarding is configured entirely in Outlook. No credentials or API keys are needed for Exchange access — everything comes through Gmail IMAP.

### Sources
- [Microsoft deprecation of basic auth](https://learn.microsoft.com/en-us/exchange/clients-and-mobile-in-exchange-online/deprecation-of-basic-authentication-exchange-online)
- [Microsoft modern auth enforcement 2026](https://www.getmailbird.com/microsoft-modern-authentication-enforcement-email-guide/)

---

## 4. Setting Environment Variables for Claude Code

Once you have your credentials, set them before starting Claude Code. The safest approach is to set them in your current shell session:

```bash
# === TIER 3 CREDENTIALS (new) ===

# Gemini API Key (Tier 3 - web search and reasoning)
export GEMINI_API_KEY='AIzaSyD-your-key-here'

# Gmail IMAP (Tier 3 - read-only email access for both Gmail and forwarded Exchange)
export GMAIL_IMAP_USER='philkoh.admin@gmail.com'
export GMAIL_IMAP_APP_PASSWORD='abcdefghijklmnop'

# === ALREADY CONFIGURED (for reference) ===

# Gmail SMTP (Tier 1 - outgoing email, already in vault)
export SMTP_USER='philkoh.admin@gmail.com'
export SMTP_PASSWORD='your-gmail-smtp-app-password'

# Telegram test scripts (already configured)
export TELEGRAM_API_ID='your-api-id'
export TELEGRAM_API_HASH='your-api-hash'
export TELEGRAM_PHONE='+1xxxxxxxxxx'
```

Then start Claude Code:
```bash
claude
```

Claude Code will use `$VARIABLE` expansion in shell commands to inject these into the vault on Tier 1 without the values ever appearing in the chat.

---

## 5. Quick Reference: All Environment Variables

### New credentials to set up now

| Variable | Purpose | Where to Get It |
|----------|---------|-----------------|
| `GEMINI_API_KEY` | Tier 3 Gemini web search | [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey) |
| `GMAIL_IMAP_USER` | Tier 3 Gmail + Exchange reading | Your Gmail address (philkoh.admin@gmail.com) |
| `GMAIL_IMAP_APP_PASSWORD` | Tier 3 Gmail IMAP auth | [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) |

### Already configured (no action needed)

| Variable | Purpose | Status |
|----------|---------|--------|
| `SMTP_USER` | Tier 1 outgoing email | Already in vault |
| `SMTP_PASSWORD` | Tier 1 outgoing email | Already in vault |
| `TELEGRAM_API_ID` | Telethon test scripts | Already set |
| `TELEGRAM_API_HASH` | Telethon test scripts | Already set |
| `TELEGRAM_PHONE` | Telethon test scripts | Already set |

### Manual setup (no env var needed)

| Item | Action | Where |
|------|--------|-------|
| Exchange forwarding | Forward phil@emtera.com to Gmail | [outlook.office.com](https://outlook.office.com) > Settings > Mail > Forwarding |
| Gmail filter | Label forwarded Exchange emails | Gmail > Search options > Create filter |

---

*This guide was generated on 2026-03-23 based on current service documentation. Microsoft and Google may change their interfaces — check the source links if anything looks different.*
