#!/usr/bin/env python3
"""Verify NanoClaw web lockdown: basic chat should work, web tools should fail."""

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
                if len(text) > 600:
                    print(f"REPLY ({elapsed}s):\n{text[:600]}\n... [{len(text)} chars total]")
                else:
                    print(f"REPLY ({elapsed}s):\n{text}")
                return text, elapsed
        await asyncio.sleep(3)

    elapsed = int(time.time() - send_time)
    print(f"TIMEOUT after {elapsed}s - no reply")
    return None, elapsed


async def main():
    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.connect()

    if not await client.is_user_authorized():
        print("Not logged in.")
        return 1

    me = await client.get_me()
    print(f"Logged in as: {me.first_name}")

    tests = [
        ("Basic chat (should work)", "What is 2+2? Reply with just the number.", True),
        ("Bash tool (should work)", "Run 'echo hello from nanoclaw' in bash and show the output.", True),
        ("WebSearch (should be blocked)", "Use the WebSearch tool to search for 'test query'. Tell me if you can or cannot use that tool.", False),
        ("WebFetch (should be blocked)", "Use the WebFetch tool to fetch https://example.com. Tell me if you can or cannot use that tool.", False),
        ("Browser (should be blocked)", "Use agent-browser to open https://example.com. Tell me if you can or cannot do this.", False),
        ("Curl from bash (should fail at network)", "Run 'curl -s --max-time 10 https://example.com' in bash and tell me what happens.", False),
    ]

    results = []
    for name, message, expect_success in tests:
        if results:
            print("\n--- waiting 5s ---")
            await asyncio.sleep(5)
        reply, elapsed = await send_and_wait(client, message)

        if reply is None:
            status = "FAIL (timeout)"
        elif expect_success:
            status = "PASS" if reply else "FAIL"
        else:
            # For "should be blocked" tests, we expect a reply explaining the tool is unavailable
            # or that the network request failed
            blocked_indicators = [
                "not available", "don't have", "cannot", "can't", "unable",
                "not able", "no access", "blocked", "denied", "not authorized",
                "timed out", "timeout", "connection", "error", "failed",
                "not have access", "do not have", "isn't available",
            ]
            is_blocked = any(ind in reply.lower() for ind in blocked_indicators)
            status = "PASS (blocked)" if is_blocked else "FAIL (NOT blocked)"

        results.append((name, status, elapsed))

    print(f"\n\n{'='*60}")
    print("LOCKDOWN TEST SUMMARY")
    print(f"{'='*60}")
    for name, status, elapsed in results:
        print(f"  {status:25s} ({elapsed:3d}s)  {name}")

    passed = sum(1 for _, s, _ in results if s.startswith("PASS"))
    print(f"\n{passed}/{len(results)} tests passed")

    await client.disconnect()
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
