#!/usr/bin/env python3
"""Test browser and web capabilities of NanoClaw bot."""

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

TIMEOUT = 180


async def send_and_wait(client, message, timeout=TIMEOUT):
    print(f"\n{'='*60}")
    print(f"SENDING: {message}")
    print(f"{'='*60}")

    send_time = time.time()
    await client.send_message(BOT_USERNAME, message)

    while time.time() - send_time < timeout:
        messages = await client.get_messages(BOT_USERNAME, limit=5)
        for msg in messages:
            if not msg.out and msg.date.timestamp() > send_time - 2:
                elapsed = int(time.time() - send_time)
                text = msg.text or "(no text)"
                if len(text) > 800:
                    print(f"REPLY ({elapsed}s):")
                    print(text[:800] + f"\n... [{len(text)} chars total]")
                else:
                    print(f"REPLY ({elapsed}s):")
                    print(text)
                return text, elapsed
        await asyncio.sleep(3)

    elapsed = int(time.time() - send_time)
    print(f"TIMEOUT after {elapsed}s - no reply")
    return None, elapsed


async def main():
    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.connect()

    if not await client.is_user_authorized():
        print("Not logged in. Run tg_login.py first.")
        return 1

    me = await client.get_me()
    print(f"Logged in as: {me.first_name}")

    tests = [
        ("WebSearch", "Search the web for 'Anthropic Claude 2026' and give me a brief summary of the top results."),
        ("WebFetch", "Fetch https://httpbin.org/get and show me the JSON response."),
        ("Browser skill", "Use agent-browser to open https://example.com, take a snapshot, and tell me what's on the page."),
    ]

    results = []
    for name, message in tests:
        if results:
            print("\n--- waiting 5s before next test ---")
            await asyncio.sleep(5)
        reply, elapsed = await send_and_wait(client, message)
        status = "PASS" if reply else "FAIL (timeout)"
        results.append((name, status, elapsed))

    print(f"\n\n{'='*60}")
    print("TEST SUMMARY")
    print(f"{'='*60}")
    for name, status, elapsed in results:
        print(f"  {status:20s} ({elapsed:3d}s)  {name}")

    passed = sum(1 for _, s, _ in results if s == "PASS")
    print(f"\n{passed}/{len(results)} tests passed")

    await client.disconnect()
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
