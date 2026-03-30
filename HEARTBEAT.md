# PhilClaw Heartbeat Checklist

This file defines what the heartbeat daemon checks on each cycle.
The heartbeat script (`dispatch/heartbeat.sh`) runs these checks automatically.

## Active Checks

1. **NanoClaw service** — Verify systemd service is active
2. **Tier 2 (PortalClaw)** — SSH reachability to 52.70.246.155
3. **Tier 3 (ReaderClaw)** — SSH reachability to 13.218.4.41
4. **Disk usage** — Alert if Tier 1 root partition exceeds 85%
5. **Memory reminders** — Scan MEMORY.md for items due today
6. **Docker daemon** — Verify Docker is running (required for container sessions)

## Reporting Rules

- **Alert mode** (default): Only message Phil when an issue is detected
- **Verbose mode** (`--verbose`): Always report, even when all checks pass (used for testing)
- Messages are sent via Telegram Bot API directly (no LLM session needed)
- All heartbeat activity is logged to `/home/ubuntu/logs/ops/dispatch.log`

## Schedule

- **Testing**: Every 60 seconds (verbose mode)
- **Production**: Every 15 minutes (alert-only mode)

## Future Enhancements

- Email urgency scan (run email-summary.sh, flag URGENT items)
- API usage threshold alerts
- Credential expiry warnings
- Tier 2/3 container health (not just SSH reachability)
