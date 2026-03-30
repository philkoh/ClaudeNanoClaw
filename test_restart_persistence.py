#!/usr/bin/env python3
"""Test that todo list and bot behavior persist through a service restart.

Flow:
  1. Add a unique test item to the todo list
  2. Verify it appears in the list
  3. Restart the NanoClaw service on Tier 1 via SSH
  4. Wait for the bot to come back online
  5. Ask for the todo list again — confirm test item survived
  6. Ask a follow-up that requires the bot to be functional
  7. Clean up the test item
"""

import asyncio
import os
import subprocess
import sys
import time

from telethon import TelegramClient

API_ID = int(os.environ["TELEGRAM_API_ID"])
API_HASH = os.environ["TELEGRAM_API_HASH"]
PHONE = os.environ["TELEGRAM_PHONE"]
BOT_USERNAME = "PhilLightsailOpenClawBot"
SESSION_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "telethon_session")

SSH_KEY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "NanoClaw-Tier1-Key.pem")
TIER1_HOST = "ubuntu@174.129.11.27"

RESULTS = []


def ssh_cmd(cmd, timeout=30):
    """Run a command on Tier 1 via SSH and return output."""
    # Wrap with XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS for systemctl --user
    wrapped = f'export XDG_RUNTIME_DIR=/run/user/$(id -u); export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus; {cmd}'
    full = ["ssh", "-i", SSH_KEY, "-o", "StrictHostKeyChecking=no", TIER1_HOST, wrapped]
    result = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
    return result.stdout.strip(), result.returncode


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

    test_item = f"RESTART-TEST-{int(time.time()) % 100000}"

    print("\n" + "=" * 60)
    print("RESTART PERSISTENCE TEST")
    print(f"Test item: {test_item}")
    print("=" * 60)

    # ================================================================
    # PHASE 1: PRE-RESTART — Write and verify
    # ================================================================

    # TEST 1: Add test item
    reply, elapsed = await send_and_wait(
        client,
        f"Add '{test_item}' to my coding todo list please.",
        timeout=180
    )
    if reply:
        has_confirm = any(kw in reply.lower() for kw in [
            "added", "done", "updated", test_item.lower()
        ])
        record("1. Pre-restart: add todo item", has_confirm, f"({elapsed}s)")
    else:
        record("1. Pre-restart: add todo item", False, f"timeout ({elapsed}s)")
        print("FATAL: Cannot continue without adding the item first.")
        await client.disconnect()
        return 1

    await asyncio.sleep(6)

    # TEST 2: Verify it's there before restart
    reply, elapsed = await send_and_wait(
        client,
        "Show me my coding todo list.",
        timeout=180
    )
    pre_restart_found = False
    if reply:
        pre_restart_found = test_item.lower() in reply.lower()
        record("2. Pre-restart: verify item in list", pre_restart_found,
               f"({elapsed}s)")
    else:
        record("2. Pre-restart: verify item in list", False, f"timeout ({elapsed}s)")

    if not pre_restart_found:
        print("WARNING: Item not found pre-restart — continuing anyway to test restart.")

    await asyncio.sleep(4)

    # ================================================================
    # PHASE 2: RESTART the NanoClaw service
    # ================================================================
    print(f"\n{'='*60}")
    print("RESTARTING NanoClaw service on Tier 1...")
    print(f"{'='*60}")

    # Verify MEMORY.md has our item before restart
    mem_out, rc = ssh_cmd("cat ~/NanoClaw/groups/telegram_main/MEMORY.md")
    mem_has_item = test_item in mem_out
    record("3. Memory file has item before restart", mem_has_item,
           f"(on-disk check, rc={rc})")
    if mem_has_item:
        print(f"  Confirmed: {test_item} found in MEMORY.md on disk")

    # Restart the service — stop (kill if needed), then start
    print("  Stopping service...")
    out, rc = ssh_cmd("systemctl --user stop nanoclaw.service --no-block", timeout=15)
    await asyncio.sleep(5)
    # Kill any lingering process
    ssh_cmd("systemctl --user kill nanoclaw.service 2>/dev/null; sleep 2", timeout=15)
    await asyncio.sleep(3)
    print("  Starting service...")
    out, rc = ssh_cmd("systemctl --user start nanoclaw.service", timeout=30)
    print(f"  systemctl start: rc={rc}")
    record("4. Service restart command", rc == 0, f"rc={rc}")

    # Wait for service to come back up
    print("  Waiting for service to come back up...")
    await asyncio.sleep(10)

    for attempt in range(6):
        out, rc = ssh_cmd("systemctl --user is-active nanoclaw.service")
        if out.strip() == "active":
            print(f"  Service is active (attempt {attempt+1})")
            break
        print(f"  Not yet active: '{out}' (attempt {attempt+1})")
        await asyncio.sleep(5)

    out, rc = ssh_cmd("systemctl --user is-active nanoclaw.service")
    record("5. Service back up after restart", out.strip() == "active",
           f"status={out.strip()}")

    # Give it a moment to initialize
    print("  Waiting 15s for bot to initialize...")
    await asyncio.sleep(15)

    # ================================================================
    # PHASE 3: POST-RESTART — Verify persistence
    # ================================================================

    # TEST 6: Check memory file still has item on disk
    mem_out, rc = ssh_cmd("cat ~/NanoClaw/groups/telegram_main/MEMORY.md")
    mem_has_item_post = test_item in mem_out
    record("6. Memory file has item after restart", mem_has_item_post,
           f"(on-disk check)")

    # TEST 7: Ask bot for todo list — does it remember?
    reply, elapsed = await send_and_wait(
        client,
        "Show me my coding todo list please.",
        timeout=300
    )
    post_restart_found = False
    if reply:
        post_restart_found = test_item.lower() in reply.lower()
        has_list = any(kw in reply.lower() for kw in ["coding", "todo", "list"])
        record("7. Post-restart: bot returns todo list", has_list, f"({elapsed}s)")
        record("8. Post-restart: test item survived restart", post_restart_found,
               f"({elapsed}s) {'FOUND' if post_restart_found else 'MISSING'}")
    else:
        record("7. Post-restart: bot returns todo list", False, f"timeout ({elapsed}s)")
        record("8. Post-restart: test item survived restart", False, "bot unresponsive")

    await asyncio.sleep(6)

    # TEST 9: Functional check — can the bot do a simple task post-restart?
    reply, elapsed = await send_and_wait(
        client,
        "What time is it right now?",
        timeout=180
    )
    if reply:
        has_response = len(reply) > 5
        record("9. Post-restart: bot functional (simple query)", has_response,
               f"({elapsed}s)")
    else:
        record("9. Post-restart: bot functional (simple query)", False,
               f"timeout ({elapsed}s)")

    await asyncio.sleep(6)

    # ================================================================
    # PHASE 4: CLEANUP
    # ================================================================
    reply, elapsed = await send_and_wait(
        client,
        f"Remove '{test_item}' from my coding todo list. It was just a test.",
        timeout=180
    )
    if reply:
        has_confirm = any(kw in reply.lower() for kw in [
            "removed", "done", "updated", "deleted"
        ])
        record("10. Cleanup: remove test item", has_confirm, f"({elapsed}s)")
    else:
        record("10. Cleanup: remove test item", False, f"timeout ({elapsed}s)")

    await client.disconnect()

    # ---- Summary ----
    print(f"\n{'='*60}")
    print("TEST SUMMARY — RESTART PERSISTENCE")
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
