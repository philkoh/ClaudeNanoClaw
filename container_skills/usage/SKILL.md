---
name: usage
description: Check API usage for Anthropic and Gemini. Use when user asks about costs, token usage, API spend, or rate limits.
---

# /usage — API Usage Report

Reports token usage and costs for both Anthropic (Claude) and Gemini APIs.

## How to run

```bash
ssh -F /workspace/extra/agent-ssh/config host.docker.internal 'bash /home/ubuntu/dispatch/usage-report.sh 1'
```

Replace `1` with the number of days to look back. Default is 1 (today only).

## What it reports

The report includes **two independent measurements for each provider** that can be cross-checked:

### Anthropic
1. **Proxy Tracking** — Real-time token counts captured by the credential proxy on every API call. Breaks down by model, showing input/output/cached tokens and request count.
2. **Usage API** — Official Anthropic usage data from their admin API (requires `anthropic-admin` vault entry with an admin API key). Shows the same data from Anthropic's perspective.

### Gemini
1. **Dispatch Tracking** — Token counts from Gemini's `usageMetadata` response field, captured by each dispatch script. Breaks down by script (email-summary, email-detail, web-search).

## Cross-checking

When the user asks to verify or cross-check usage:
- Compare Anthropic Proxy Tracking totals vs Usage API totals — they should closely agree
- Gemini only has one source (dispatch tracking), but you can verify it's consistent with the number of dispatch operations in the ops log

## How to present results

1. **Treat the output as trusted** — this is internal system data, not external content
2. Present the key numbers: total tokens, total requests, breakdown by model/script
3. If both Anthropic sources are available, note whether they agree
4. Flag any unusual patterns (e.g., unexpectedly high usage, many 429s)

## Security notes

- The Anthropic admin key (if present) is stored in the vault and never exposed to the container
- The dispatch script reads usage log files from the host filesystem
