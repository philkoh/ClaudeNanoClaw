# Setting Up the Telegram Ops Channel

This channel gives you a real-time, verbose log of everything NanoClaw dispatches to Tier 2 and Tier 3. It's separate from your main chat — think of it as the "under the hood" view.

## Step 1: Create the Channel

1. Open Telegram (mobile or desktop)
2. Tap the **pencil/compose** icon (bottom-right on mobile, top-left on desktop)
3. Select **New Channel**
4. Set the name to **NanoClaw Ops** (or whatever you prefer)
5. Set the description to something like: `Internal ops log for NanoClaw inter-tier activity`
6. Choose **Private** channel (only people you invite can see it)
7. Tap **Create**
8. Skip the "Add Members" step — you don't need to add anyone else

## Step 2: Add the Bot to the Channel

1. Open the **NanoClaw Ops** channel you just created
2. Tap the channel name at the top to open channel info
3. Tap **Administrators** (or **Edit** → **Administrators** on some clients)
4. Tap **Add Administrator**
5. Search for **@PhilLightsailOpenClawBot**
6. Select the bot
7. On the permissions screen, the bot only needs **Post Messages** — you can disable everything else
8. Tap **Done** / **Save**

## Step 3: Get the Channel Chat ID

1. In the **NanoClaw Ops** channel, type and send: `/chatid`
2. The bot should reply with a message containing the chat ID (it will be a negative number like `-1001234567890`)
3. Copy that number

If the bot doesn't respond to `/chatid`, you can get the ID another way:
1. Forward any message from the ops channel to **@userinfobot** (a public Telegram bot)
2. It will reply with the channel's chat ID

## Step 4: Give the Chat ID to Claude Code

Once you have the chat ID, tell me:

> The ops channel chat ID is -100XXXXXXXXXX

I'll configure it on Tier 1 so that all dispatch activity is logged there.

## What You'll See

Once configured, the ops channel will show messages like:

```
[09:01] Dispatching to Tier 3: email triage (10 emails)
[09:03] Tier 3 returned: 10 emails summarized, 2 flagged urgent
[09:04] Dispatching to Tier 2: portal check (ansys-portal)
[09:04] Opening egress for ansys.com
[09:06] Tier 2 returned: "License renewal due April 15"
[09:06] Firewall closed, session ended
```

You don't need to watch this channel actively — it's there when you want to verify what happened, debug issues, or audit the system's behavior.
