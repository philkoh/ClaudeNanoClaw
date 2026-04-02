#!/usr/bin/env python3
"""End-to-end test: send email draft request via Telegram to PhilClaw bot."""

import asyncio
import os
import sys
import time

from telethon import TelegramClient

API_ID = int(os.environ["TELEGRAM_API_ID"])
API_HASH = os.environ["TELEGRAM_API_HASH"]
PHONE = os.environ["TELEGRAM_PHONE"]
BOT_USERNAME = "PhilLightsailOpenClawBot"
SESSION_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "telethon_session")


async def send_and_wait(client, message, timeout=300):
    """Send message to bot and wait for reply."""
    print(f"\n{'='*60}")
    print(f"SENDING: {message}")
    print(f"{'='*60}")
    send_time = time.time()
    await client.send_message(BOT_USERNAME, message)

    last_check = ""
    while time.time() - send_time < timeout:
        messages = await client.get_messages(BOT_USERNAME, limit=5)
        for msg in messages:
            if not msg.out and msg.date.timestamp() > send_time - 2:
                text = msg.text or "(no text)"
                if text != last_check:
                    elapsed = int(time.time() - send_time)
                    print(f"\nREPLY ({elapsed}s):\n{text[:2000]}")
                    if len(text) > 2000:
                        print(f"  ... [{len(text)} chars total]")
                    return text, elapsed
        await asyncio.sleep(4)
    print(f"\nTIMEOUT after {timeout}s")
    return None, int(time.time() - send_time)


async def main():
    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.connect()
    if not await client.is_user_authorized():
        print("ERROR: Not logged in. Run the auth script first.")
        return 1

    print("Connected to Telegram. Sending email draft request...")

    # Test: Ask PhilClaw to draft an email
    reply, elapsed = await send_and_wait(
        client,
        "Draft an email to phil@emtera.com with subject 'Test draft from Telegram' and body 'This is a test of the email drafting pipeline via Telegram.'",
        timeout=300
    )

    if reply:
        # Check for success indicators
        success_keywords = ["draft", "created", "saved", "drafts folder", "outlook", "exchange"]
        has_success = any(kw in reply.lower() for kw in success_keywords)
        error_keywords = ["error", "failed", "unable", "cannot", "sorry"]
        has_error = any(kw in reply.lower() for kw in error_keywords)

        print(f"\n{'='*60}")
        print(f"RESULT: {'PASS' if has_success and not has_error else 'NEEDS REVIEW'}")
        print(f"  Success indicators found: {has_success}")
        print(f"  Error indicators found: {has_error}")
        print(f"  Response time: {elapsed}s")
        print(f"{'='*60}")
        return 0 if has_success and not has_error else 1
    else:
        print(f"\nFAILED: No response within timeout ({elapsed}s)")
        return 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
