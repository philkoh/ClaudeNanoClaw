# NanoClaw Project — Claude Code Workstation

This is the admin workstation for Philip Koh's three-tier AI admin assistant.

## Architecture
- **Tier 1 (NanoClaw orchestrator):** 174.129.11.27 — SSH: `ssh -i NanoClaw-Tier1-Key.pem ubuntu@174.129.11.27`
- **Tier 2 (OpenClaw portal automation):** 52.70.246.155 — SSH via Tier 1: `ssh -i NanoClaw-Tier1-Key.pem ubuntu@174.129.11.27 "ssh tier2 '<cmd>'"`
- **Tier 3 (Gemini email/search):** 13.218.4.41 — SSH via Tier 1: `ssh -i NanoClaw-Tier1-Key.pem ubuntu@174.129.11.27 "ssh tier3 '<cmd>'"`
- **This workstation:** 100.49.113.22 — admin/testing VM

## Key Files
- `philip_koh_multi_agent_plan.md` — Full architecture plan
- `NanoClaw-Tier1-Key.pem` — SSH key for all VMs (chmod 600)
- `dispatch_scripts/` — Host dispatch scripts deployed to Tier 1
- `container_skills/` — NanoClaw container skills deployed to Tier 1
- `tier3_scripts/` — Scripts deployed to Tier 3
- `test_phase3.py` — Telegram integration tests (needs telethon in venv)
- `telethon_session.session` — Authenticated Telegram session for testing

## Required Environment Variables
Set these before running tests or interacting with the system:
- ANTHROPIC_API_KEY — Anthropic API key (for Claude Code and Tier 2)
- GEMINI_API_KEY — Google Gemini API key (for Tier 3)
- GMAIL_IMAP_USER — Gmail address for IMAP (philkoh.admin@gmail.com)
- GMAIL_IMAP_APP_PASSWORD — Gmail app password for IMAP
- SMTP_USER — Gmail address for outgoing email
- SMTP_PASSWORD — Gmail app password for SMTP
- TELEGRAM_API_ID — Telegram API ID (for Telethon tests)
- TELEGRAM_API_HASH — Telegram API hash
- TELEGRAM_PHONE — Phone number for Telegram
- TELEGRAM_BOT_TOKEN — NanoClaw bot token

## Security Rules
- NEVER send credentials through chat — use env var expansion (`$VAR`)
- NEVER commit .pem files, .session files, or .env files
- All SSH to Tier 2/3 goes through Tier 1 (jump host)
