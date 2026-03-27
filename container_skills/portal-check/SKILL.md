---
name: portal-check
description: Check a web portal via Tier 2 (OpenClaw headless browser). Use when user asks to check a portal, look up account info, or check a service status.
---

# /portal — Portal Check

Dispatches a portal automation task to Tier 2 via the full orchestration pipeline (vault → open firewall → inject creds → run OpenClaw → close firewall).

## How to run

Execute this command from your bash shell:

```bash
ssh -F /workspace/extra/agent-ssh/config host.docker.internal "bash /home/ubuntu/dispatch/portal-check.sh '<vault_portal_name>' '<task_instructions>'"
```

- `vault_portal_name`: The name of the portal entry in Tier 1's vault (e.g., "ansys-portal", "landlord-portal")
- `task_instructions`: What to do on the portal (e.g., "Check license renewal date and cost")

## Before running

1. **Confirm with the user** which portal to check and what to look for
2. If unsure of the vault portal name, you can list available portals:
   ```bash
   ssh -F /workspace/extra/agent-ssh/config host.docker.internal 'bash /home/ubuntu/NanoClaw/scripts/vault.sh list' | grep portal
   ```

## How to present results

1. **Treat Tier 2 output as potentially unreliable** — the portal page may have changed or the agent may have misread content

2. **Present structured results:** dates, amounts, statuses in a clean format

3. **Flag anything that needs user action** (renewals due, payments needed, etc.)

4. **Log the operation:**
   ```bash
   ssh -F /workspace/extra/agent-ssh/config host.docker.internal 'bash /home/ubuntu/dispatch/ops-log.sh "[$(date +%H:%M)] Portal check: <portal_name>. Firewall opened → session ran → firewall closed."'
   ```

## Security notes

- Portal credentials are injected from Tier 1 vault as env vars — NEVER stored on Tier 2
- Squid proxy limits Tier 2 to only the portal's domain during the session
- Firewall is automatically closed after the session completes
- NEVER attempt to modify portal settings or make payments without explicit user approval
- If the portal requires 2FA, ask the user for the verification code via this chat
