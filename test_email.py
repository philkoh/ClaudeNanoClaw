#!/usr/bin/env python3
"""End-to-end email test: send draft request, approve, verify send."""

import asyncio
import os
import sys
import time

from telethon import TelegramClient

API_ID = int(os.environ["TELEGRAM_API_ID"])
API_HASH = os.environ["TELEGRAM_API_HASH"]
PHONE = os.environ["TELEGRAM_PHONE"]
SMTP_USER = os.environ["SMTP_USER"]
BOT_USERNAME = "PhilLightsailOpenClawBot"
SESSION_FILE = os.path.join(os.path.dirname(__file__), "telethon_session")

TIMEOUT = 180  # seconds to wait for each reply


async def wait_for_reply(client, after_ts, label="reply"):
    """Wait for a new incoming message from the bot after the given timestamp."""
    print(f"Waiting up to {TIMEOUT}s for {label}...")
    start = time.time()
    while time.time() - start < TIMEOUT:
        messages = await client.get_messages(BOT_USERNAME, limit=1)
        if messages and not messages[0].out and messages[0].date.timestamp() > after_ts - 5:
            print(f"\nBot {label} ({int(time.time() - start)}s):")
            print(messages[0].text[:500])
            return messages[0]
        await asyncio.sleep(3)
    print(f"\nNo {label} after {TIMEOUT}s.")
    return None


async def main():
    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.start(phone=PHONE)
    print(f"Logged in as: {(await client.get_me()).first_name}")

    # Step 1: Send email draft request
    ts = time.time()
    draft_request = (
        f"Draft an email using vault entry gmail-smtp. "
        f"Send to {SMTP_USER} with subject 'NanoClaw Email Test' "
        f"and body 'Hello! This is an automated test of the NanoClaw email pipeline. "
        f"Sent at {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}.' "
    )
    print(f"Sending draft request to @{BOT_USERNAME}...")
    await client.send_message(BOT_USERNAME, draft_request)

    # Step 2: Wait for draft approval prompt
    reply = await wait_for_reply(client, ts, "draft/approval prompt")
    if not reply:
        await client.disconnect()
        return 1

    # Step 3: Send YES to approve
    ts2 = time.time()
    print("\nSending YES to approve...")
    await client.send_message(BOT_USERNAME, "YES")

    # Step 4: Wait for send confirmation
    confirm = await wait_for_reply(client, ts2, "send confirmation")
    if not confirm:
        await client.disconnect()
        return 1

    print("\n--- Email test complete ---")
    await client.disconnect()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
