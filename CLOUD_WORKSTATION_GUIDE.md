# Claude Code Cloud Workstation — Connection Guide

**VM:** ClaudeCode-Workstation
**Static IP:** 100.49.113.22
**Region:** us-east-1a (N. Virginia)
**OS:** Ubuntu 24.04 LTS
**Size:** 4GB RAM / 2 vCPU ($24/mo)
**SSH Key:** NanoClaw-Tier1-Key.pem (same key as Tier 1)

---

## Step 1: Get the SSH Key

You need the `NanoClaw-Tier1-Key.pem` file on whatever device you're connecting from. This is the same key used for all your Lightsail instances.

If you don't have it on a device, you can copy it from any machine that does:
```bash
scp NanoClaw-Tier1-Key.pem user@other-device:~/.ssh/
```

---

## Step 2: Connect from Linux PC

### First-time setup
```bash
# Copy the key to your SSH directory
cp NanoClaw-Tier1-Key.pem ~/.ssh/
chmod 600 ~/.ssh/NanoClaw-Tier1-Key.pem

# Add a shortcut to your SSH config
cat >> ~/.ssh/config << 'EOF'
Host claude-workstation
  HostName 100.49.113.22
  User ubuntu
  IdentityFile ~/.ssh/NanoClaw-Tier1-Key.pem
EOF
```

### Connect
```bash
# Standard SSH
ssh claude-workstation

# Or with mosh (better for unstable connections)
mosh --ssh="ssh -i ~/.ssh/NanoClaw-Tier1-Key.pem" ubuntu@100.49.113.22
```

### Resume your Claude Code session
```bash
# Attach to the tmux session (persists across disconnects)
tmux attach -t claude || tmux new -s claude

# Inside tmux, navigate to project and start Claude Code
cd ~/ClaudeNanoClawCreator
claude
```

---

## Step 3: Connect from Windows PC

### Option A: Windows Terminal + OpenSSH (recommended)

Windows 10/11 has OpenSSH built in.

1. Open **Windows Terminal** (or PowerShell)
2. Copy the .pem key to your user directory:
   ```powershell
   mkdir $env:USERPROFILE\.ssh -ErrorAction SilentlyContinue
   copy NanoClaw-Tier1-Key.pem $env:USERPROFILE\.ssh\
   ```
3. Fix permissions (Windows requires this). Run in **PowerShell**:
   ```powershell
   $keyPath = "$env:USERPROFILE\.ssh\NanoClaw-Tier1-Key.pem"
   icacls $keyPath /inheritance:r
   icacls $keyPath /grant "${env:USERNAME}:(R)"
   ```
4. Add to SSH config (paste this exactly — the closing `"@` must be on its own line with no spaces before it):
   ```powershell
   Add-Content $env:USERPROFILE\.ssh\config "`nHost claude-workstation`n  HostName 100.49.113.22`n  User ubuntu`n  IdentityFile ~/.ssh/NanoClaw-Tier1-Key.pem"
   ```
5. Connect:
   ```powershell
   ssh claude-workstation
   ```
6. Inside the VM:
   ```bash
   tmux attach -t claude || tmux new -s claude
   cd ~/ClaudeNanoClawCreator && claude
   ```

### Option B: PuTTY

1. Download PuTTY from https://www.putty.org/
2. Convert the .pem to .ppk:
   - Open **PuTTYgen**
   - Click **Load** → select `NanoClaw-Tier1-Key.pem` (change filter to "All Files")
   - Click **Save private key** → save as `NanoClaw-Tier1-Key.ppk`
3. In PuTTY:
   - **Session** → Host Name: `100.49.113.22`, Port: `22`
   - **Connection → SSH → Auth → Credentials** → Private key file: browse to `.ppk`
   - **Connection → Data** → Auto-login username: `ubuntu`
   - **Session** → Saved Sessions: type `claude-workstation`, click **Save**
4. Click **Open** to connect

---

## Step 4: Connect from iPhone

### Option A: Termius (recommended — free tier works)

1. Install **Termius** from the App Store
2. Open Termius → tap **+** → **New Host**
3. Fill in:
   - **Label:** Claude Workstation
   - **Hostname:** 100.49.113.22
   - **Username:** ubuntu
4. Tap **Keys** → **+** → **Import from Files**
   - Transfer the .pem to your iPhone first (via AirDrop, iCloud, email attachment, etc.)
   - Select `NanoClaw-Tier1-Key.pem`
5. Save and tap to connect
6. Once connected:
   ```bash
   tmux attach -t claude || tmux new -s claude
   cd ~/ClaudeNanoClawCreator && claude
   ```

### Option B: Blink Shell ($19.99 — better for power users)

1. Install **Blink Shell** from the App Store
2. Open Settings → Keys → **+** → Import key from file
   - Import `NanoClaw-Tier1-Key.pem`
3. Settings → Hosts → **+**
   - **Host:** claude-workstation
   - **Hostname:** 100.49.113.22
   - **User:** ubuntu
   - **Key:** select the imported key
4. From the Blink terminal:
   ```
   ssh claude-workstation
   ```
5. Blink also supports **mosh** natively:
   ```
   mosh ubuntu@100.49.113.22
   ```

---

## Step 5: Set Environment Variables

Before using Claude Code on the workstation, you need to set your API keys and credentials. Create a `.env` file (the tmux session will source it).

SSH into the workstation and run:

```bash
cat > ~/.env << 'EOF'
# === Required for Claude Code ===
export ANTHROPIC_API_KEY="your-anthropic-api-key-here"

# === Required for Tier 3 (email + web search) ===
export GEMINI_API_KEY="your-gemini-api-key-here"
export GMAIL_IMAP_USER="philkoh.admin@gmail.com"
export GMAIL_IMAP_APP_PASSWORD="your-gmail-imap-app-password-here"

# === Required for Tier 1 (outgoing email) ===
export SMTP_USER="philkoh.admin@gmail.com"
export SMTP_PASSWORD="your-gmail-smtp-app-password-here"

# === Required for Telegram testing (Telethon) ===
export TELEGRAM_API_ID="your-telegram-api-id-here"
export TELEGRAM_API_HASH="your-telegram-api-hash-here"
export TELEGRAM_PHONE="your-phone-number-here"
export TELEGRAM_BOT_TOKEN="your-bot-token-here"
EOF

# Lock permissions
chmod 600 ~/.env

# Add auto-source to bashrc
echo '[ -f ~/.env ] && source ~/.env' >> ~/.bashrc
```

Then source it:
```bash
source ~/.env
```

**IMPORTANT:** Replace each `your-...-here` with the actual values. These are the same credentials you had set in your previous Claude Code session. Check your password manager or the original setup notes.

---

## Step 6: Start Working

```bash
# Connect (from any device)
ssh claude-workstation    # or: mosh ubuntu@100.49.113.22

# Attach to persistent session
tmux attach -t claude || tmux new -s claude

# Start Claude Code in the project directory
cd ~/ClaudeNanoClawCreator
claude
```

### tmux Cheat Sheet
| Action | Keys |
|--------|------|
| Detach (leave session running) | `Ctrl+b` then `d` |
| New window | `Ctrl+b` then `c` |
| Switch windows | `Ctrl+b` then `0-9` |
| Scroll up | `Ctrl+b` then `[`, then arrow keys (press `q` to exit) |
| Split horizontal | `Ctrl+b` then `"` |
| Split vertical | `Ctrl+b` then `%` |

### Key point
When you disconnect (close the app, lose wifi, etc.), your Claude Code session stays alive inside tmux. Just reconnect and `tmux attach -t claude` to pick up exactly where you left off.

---

## Troubleshooting

**"Connection refused"** — The VM may be rebooting. Wait 30 seconds and try again.

**"Permission denied (publickey)"** — Wrong key or wrong permissions:
```bash
chmod 600 ~/.ssh/NanoClaw-Tier1-Key.pem
```

**Claude Code says "not authenticated"** — You need to set ANTHROPIC_API_KEY:
```bash
source ~/.env
claude
```

**tmux shows "no sessions"** — Start a new one:
```bash
tmux new -s claude
```

**Mosh won't connect** — The VM firewall allows UDP 60000-61000. If your network blocks UDP, use regular SSH instead.
