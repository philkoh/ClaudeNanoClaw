#!/usr/bin/env python3
"""Send a test message to NanoClaw bot and wait for a reply."""

import asyncio
import os
import sys
import time

from telethon import TelegramClient

API_ID = int(os.environ["TELEGRAM_API_ID"])
API_HASH = os.environ["TELEGRAM_API_HASH"]
PHONE = os.environ["TELEGRAM_PHONE"]
BOT_USERNAME = "PhilLightsailOpenClawBot"
SESSION_FILE = os.path.join(os.path.dirname(__file__), "telethon_session")

TIMEOUT = 120  # seconds to wait for reply


async def main():
    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.start(phone=PHONE)

    print(f"Logged in as: {(await client.get_me()).first_name}")

    # Send test message
    test_msg = f"NanoClaw self-test ping at {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}"
    print(f"Sending to @{BOT_USERNAME}: {test_msg}")
    await client.send_message(BOT_USERNAME, test_msg)

    # Wait for reply
    print(f"Waiting up to {TIMEOUT}s for reply...")
    start = time.time()
    while time.time() - start < TIMEOUT:
        messages = await client.get_messages(BOT_USERNAME, limit=1)
        if messages and messages[0].out is False and messages[0].date.timestamp() > start - 5:
            print(f"\nBot replied ({int(time.time() - start)}s):")
            print(messages[0].text)
            await client.disconnect()
            return 0
        await asyncio.sleep(3)

    print(f"\nNo reply after {TIMEOUT}s.")
    await client.disconnect()
    return 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
