#!/usr/bin/env python3
"""Quick verification: basic chat works, WebSearch blocked."""

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


async def send_and_wait(client, message, timeout=180):
    print(f"\nSENDING: {message}")
    send_time = time.time()
    await client.send_message(BOT_USERNAME, message)

    while time.time() - send_time < timeout:
        messages = await client.get_messages(BOT_USERNAME, limit=5)
        for msg in messages:
            if not msg.out and msg.date.timestamp() > send_time - 2:
                elapsed = int(time.time() - send_time)
                text = msg.text or "(no text)"
                print(f"REPLY ({elapsed}s): {text[:300]}")
                return text, elapsed
        await asyncio.sleep(3)
    print(f"TIMEOUT")
    return None, int(time.time() - send_time)


async def main():
    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.connect()
    if not await client.is_user_authorized():
        print("Not logged in.")
        return 1

    # Test 1: Basic chat
    reply, _ = await send_and_wait(client, "What is 3+3? Just the number.")
    if reply:
        print(f"  -> Basic chat: PASS")
    else:
        print(f"  -> Basic chat: FAIL")

    await asyncio.sleep(5)

    # Test 2: WebSearch
    reply, _ = await send_and_wait(client, "Try to use WebSearch to search for 'hello world'. If the tool is not available, say TOOL_UNAVAILABLE. If it works, say TOOL_WORKS.")
    if reply:
        if "UNAVAILABLE" in reply.upper() or "not available" in reply.lower() or "don't have" in reply.lower() or "cannot" in reply.lower():
            print(f"  -> WebSearch blocked: PASS")
        elif "WORKS" in reply.upper():
            print(f"  -> WebSearch blocked: FAIL (still works)")
        else:
            print(f"  -> WebSearch blocked: UNCLEAR - {reply[:200]}")

    await client.disconnect()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
