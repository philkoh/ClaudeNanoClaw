#!/usr/bin/env python3
"""Two-phase Telegram login to create a persistent session file.

Usage:
  Phase 1 (request code):  python tg_login.py
  Phase 2 (submit code):   python tg_login.py 12345
"""

import asyncio
import json
import os
import sys

from telethon import TelegramClient
from telethon.errors import SessionPasswordNeededError

API_ID = int(os.environ["TELEGRAM_API_ID"])
API_HASH = os.environ["TELEGRAM_API_HASH"]
PHONE = os.environ["TELEGRAM_PHONE"]
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SESSION_FILE = os.path.join(SCRIPT_DIR, "telethon_session")
STATE_FILE = os.path.join(SCRIPT_DIR, ".tg_login_state.json")


async def request_code():
    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.connect()

    if await client.is_user_authorized():
        me = await client.get_me()
        print(f"Already logged in as: {me.first_name}")
        await client.disconnect()
        return

    result = await client.send_code_request(PHONE)
    # Save the phone_code_hash for phase 2
    with open(STATE_FILE, "w") as f:
        json.dump({"phone_code_hash": result.phone_code_hash}, f)

    print(f"Code sent (type: {type(result.type).__name__})! Check your phone/Telegram app.")
    print(f"Then run: python tg_login.py <CODE>")
    print(f"If no code received, run: python tg_login.py --sms")
    await client.disconnect()


async def resend_sms():
    if not os.path.exists(STATE_FILE):
        print("No pending login. Run without arguments first to request a code.")
        return 1

    with open(STATE_FILE) as f:
        state = json.load(f)

    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.connect()

    result = await client.send_code_request(PHONE, force_sms=True)
    with open(STATE_FILE, "w") as f:
        json.dump({"phone_code_hash": result.phone_code_hash}, f)

    print(f"SMS resend requested (type: {type(result.type).__name__}). Check your SMS.")
    print(f"Then run: python tg_login.py <CODE>")
    await client.disconnect()
    return 0


async def submit_code(code):
    if not os.path.exists(STATE_FILE):
        print("No pending login. Run without arguments first to request a code.")
        return 1

    with open(STATE_FILE) as f:
        state = json.load(f)

    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.connect()

    try:
        await client.sign_in(PHONE, code, phone_code_hash=state["phone_code_hash"])
    except SessionPasswordNeededError:
        print("Your account has 2FA enabled. Please provide your password:")
        print("  python tg_login.py <CODE> <PASSWORD>")
        await client.disconnect()
        return 1

    me = await client.get_me()
    print(f"Logged in as: {me.first_name} (session saved)")
    os.unlink(STATE_FILE)
    await client.disconnect()
    return 0


async def submit_code_with_password(code, password):
    if not os.path.exists(STATE_FILE):
        print("No pending login. Run without arguments first to request a code.")
        return 1

    with open(STATE_FILE) as f:
        state = json.load(f)

    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.connect()

    try:
        await client.sign_in(PHONE, code, phone_code_hash=state["phone_code_hash"])
    except SessionPasswordNeededError:
        await client.sign_in(password=password)

    me = await client.get_me()
    print(f"Logged in as: {me.first_name} (session saved)")
    os.unlink(STATE_FILE)
    await client.disconnect()
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 1:
        asyncio.run(request_code())
    elif len(sys.argv) == 2 and sys.argv[1] == "--sms":
        sys.exit(asyncio.run(resend_sms()))
    elif len(sys.argv) == 2:
        sys.exit(asyncio.run(submit_code(sys.argv[1])))
    elif len(sys.argv) == 3:
        sys.exit(asyncio.run(submit_code_with_password(sys.argv[1], sys.argv[2])))
    else:
        print("Usage: python tg_login.py [--sms | CODE [PASSWORD]]")
