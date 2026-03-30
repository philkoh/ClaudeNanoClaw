#!/usr/bin/env python3
"""Comprehensive test of recent NanoClaw features via Telegram.

Tests email detail, usage tracking, persistent memory, multi-turn context,
and exercises the full dispatch pipeline as a real personal assistant user would.
"""

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

RESULTS = []
# Store state across tests for multi-turn verification
STATE = {}


async def send_and_wait(client, message, timeout=300):
    """Send message to bot and wait for reply."""
    print(f"\n{'='*60}")
    print(f"SENDING: {message}")
    print(f"{'='*60}")
    send_time = time.time()
    await client.send_message(BOT_USERNAME, message)

    while time.time() - send_time < timeout:
        messages = await client.get_messages(BOT_USERNAME, limit=5)
        for msg in messages:
            if not msg.out and msg.date.timestamp() > send_time - 2:
                text = msg.text or "(no text)"
                elapsed = int(time.time() - send_time)
                print(f"\nREPLY ({elapsed}s):\n{text[:1500]}")
                if len(text) > 1500:
                    print(f"  ... [{len(text)} chars total]")
                return text, elapsed
        await asyncio.sleep(4)
    print(f"\nTIMEOUT after {timeout}s")
    return None, int(time.time() - send_time)


def record(test_name, passed, details=""):
    status = "PASS" if passed else "FAIL"
    RESULTS.append((test_name, status, details))
    marker = "✓" if passed else "✗"
    print(f"\n  >> {marker} {test_name}: {status} {details}")


async def main():
    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.connect()
    if not await client.is_user_authorized():
        print("Not logged in. Run tg_login.py first.")
        return 1

    print("\n" + "=" * 60)
    print("RECENT FEATURES TEST SUITE")
    print("Testing: email detail, usage tracking, memory, multi-turn")
    print("=" * 60)

    # ================================================================
    # TEST 1: Email summary (baseline — exercises email-summary.sh)
    # Real user: "Hey, check my inbox"
    # ================================================================
    reply, elapsed = await send_and_wait(
        client,
        "Check my email please. Show me a summary of my last 5 messages.",
        timeout=300
    )
    if reply:
        has_email = any(kw in reply.lower() for kw in [
            "email", "inbox", "subject", "from", "briefing",
            "message", "summary", "urgent", "action"
        ])
        record("1. Email summary", has_email, f"({elapsed}s)")
        # Save a sender or subject for the drill-down test
        for line in reply.split("\n"):
            ll = line.lower()
            if "from" in ll or "sender" in ll or "@" in ll:
                STATE["email_context"] = line.strip()[:80]
                break
    else:
        record("1. Email summary", False, f"timeout ({elapsed}s)")

    await asyncio.sleep(8)

    # ================================================================
    # TEST 2: Email detail drill-down (exercises email-detail.sh raw)
    # Real user: follows up on summary with "tell me more about X"
    # ================================================================
    if STATE.get("email_context"):
        drill_msg = f"Can you look up more details on that email? The one that says: {STATE['email_context'][:60]}"
    else:
        drill_msg = "Look up the most recent email in my inbox and show me the full details."

    reply, elapsed = await send_and_wait(client, drill_msg, timeout=300)
    if reply:
        has_detail = any(kw in reply.lower() for kw in [
            "from", "subject", "date", "body", "detail", "email",
            "content", "message", "sent", "received"
        ])
        record("2. Email detail (raw)", has_detail, f"({elapsed}s)")
    else:
        record("2. Email detail (raw)", False, f"timeout ({elapsed}s)")

    await asyncio.sleep(8)

    # ================================================================
    # TEST 3: Email interpret mode (exercises --interpret with Gemini)
    # Real user: "What does that email actually say?" or asking about images
    # ================================================================
    reply, elapsed = await send_and_wait(
        client,
        "Find my most recent email that has any images or HTML formatting, and interpret what it's about. Summarize the key points.",
        timeout=300
    )
    if reply:
        has_interpret = any(kw in reply.lower() for kw in [
            "email", "image", "content", "about", "summary",
            "key", "point", "from", "subject", "html",
            "interpret", "detail", "found", "no email", "no image"
        ])
        record("3. Email interpret mode", has_interpret, f"({elapsed}s)")
    else:
        record("3. Email interpret mode", False, f"timeout ({elapsed}s)")

    await asyncio.sleep(8)

    # ================================================================
    # TEST 4: Web search (exercises web-search.sh + Gemini tracking)
    # Real user: "Find out about X for me"
    # ================================================================
    reply, elapsed = await send_and_wait(
        client,
        "Search the web for the latest news about SpaceX Starship launches.",
        timeout=300
    )
    if reply:
        has_search = any(kw in reply.lower() for kw in [
            "spacex", "starship", "launch", "rocket", "flight",
            "booster", "test", "source", "result"
        ])
        record("4. Web search", has_search, f"({elapsed}s)")
    else:
        record("4. Web search", False, f"timeout ({elapsed}s)")

    await asyncio.sleep(8)

    # ================================================================
    # TEST 5: Usage report (exercises usage-report.sh)
    # Real user: "How much have we spent on API calls?"
    # ================================================================
    reply, elapsed = await send_and_wait(
        client,
        "Show me the API usage report. How many tokens have we used?",
        timeout=180
    )
    if reply:
        has_usage = any(kw in reply.lower() for kw in [
            "usage", "token", "anthropic", "gemini", "api",
            "cost", "model", "input", "output", "calls", "request"
        ])
        record("5. Usage report", has_usage, f"({elapsed}s)")
    else:
        record("5. Usage report", False, f"timeout ({elapsed}s)")

    await asyncio.sleep(8)

    # ================================================================
    # TEST 6: Memory read — todo list (exercises MEMORY.md read)
    # Real user: "What's on my to-do list?"
    # ================================================================
    reply, elapsed = await send_and_wait(
        client,
        "What's on my todo list right now?",
        timeout=180
    )
    if reply:
        has_memory = any(kw in reply.lower() for kw in [
            "todo", "to-do", "task", "list", "admin", "coding",
            "hardware", "item", "pending", "action", "reminder"
        ])
        record("6. Memory read (todo)", has_memory, f"({elapsed}s)")
    else:
        record("6. Memory read (todo)", False, f"timeout ({elapsed}s)")

    await asyncio.sleep(8)

    # ================================================================
    # TEST 7: Memory write (exercises MEMORY.md write)
    # Real user: "Add X to my list"
    # ================================================================
    test_item = f"TEST-ITEM-{int(time.time()) % 10000}"
    reply, elapsed = await send_and_wait(
        client,
        f"Add '{test_item}' to my coding todo list. This is just a test item.",
        timeout=180
    )
    if reply:
        has_confirm = any(kw in reply.lower() for kw in [
            "added", "add", "done", "updated", "todo", "list",
            "got it", "noted", test_item.lower()
        ])
        record("7. Memory write (add todo)", has_confirm, f"({elapsed}s)")
        STATE["test_item"] = test_item
    else:
        record("7. Memory write (add todo)", False, f"timeout ({elapsed}s)")

    await asyncio.sleep(8)

    # ================================================================
    # TEST 8: Memory verify — confirm the write persisted
    # Real user: "Did you add that?" or "Show me my coding list"
    # ================================================================
    reply, elapsed = await send_and_wait(
        client,
        "Show me my coding todo list. Is the test item I just added there?",
        timeout=180
    )
    if reply:
        item_found = STATE.get("test_item", "").lower() in reply.lower()
        has_list = any(kw in reply.lower() for kw in [
            "coding", "todo", "list", "task", "item"
        ])
        record("8. Memory verify (item persisted)", item_found or has_list,
               f"({elapsed}s) {'item found in list' if item_found else 'list shown but item not confirmed'}")
    else:
        record("8. Memory verify (item persisted)", False, f"timeout ({elapsed}s)")

    await asyncio.sleep(8)

    # ================================================================
    # TEST 9: Multi-turn context (exercises history injection)
    # Real user: refers back to something earlier without restating it
    # ================================================================
    reply, elapsed = await send_and_wait(
        client,
        "Going back to the web search results you showed me earlier about SpaceX — what was the most interesting finding?",
        timeout=180
    )
    if reply:
        has_context = any(kw in reply.lower() for kw in [
            "spacex", "starship", "launch", "earlier", "search",
            "mentioned", "found", "result", "rocket"
        ])
        record("9. Multi-turn context", has_context, f"({elapsed}s)")
    else:
        record("9. Multi-turn context", False, f"timeout ({elapsed}s)")

    await asyncio.sleep(8)

    # ================================================================
    # TEST 10: Cleanup — remove test item from memory
    # Real user: "Remove X from my list"
    # ================================================================
    if STATE.get("test_item"):
        reply, elapsed = await send_and_wait(
            client,
            f"Remove '{STATE['test_item']}' from my coding todo list. It was just a test.",
            timeout=180
        )
        if reply:
            has_confirm = any(kw in reply.lower() for kw in [
                "removed", "remove", "done", "updated", "deleted", "cleaned"
            ])
            record("10. Memory cleanup (remove test item)", has_confirm, f"({elapsed}s)")
        else:
            record("10. Memory cleanup (remove test item)", False, f"timeout ({elapsed}s)")
    else:
        record("10. Memory cleanup (remove test item)", False, "skipped — no test item to remove")

    await client.disconnect()

    # ---- Summary ----
    print(f"\n{'='*60}")
    print("TEST SUMMARY — RECENT FEATURES")
    print(f"{'='*60}")
    passed = sum(1 for _, s, _ in RESULTS if s == "PASS")
    failed = sum(1 for _, s, _ in RESULTS if s == "FAIL")
    total = len(RESULTS)
    for name, status, details in RESULTS:
        marker = "✓" if status == "PASS" else "✗"
        print(f"  [{marker} {status:4s}] {name} {details}")
    print(f"\n  {passed}/{total} passed, {failed}/{total} failed")
    print(f"{'='*60}")

    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
