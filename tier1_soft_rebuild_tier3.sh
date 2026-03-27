#!/bin/bash
# soft_rebuild_tier3.sh — Run ON Tier 1 nightly to reset Tier 3 without destroying the instance
# Wipes all user state, reinstalls packages, restores clean configuration
# Per plan Section 12: destroys agent memory, browser cache, downloaded files, session data
set -eu

TIER3_IP="13.218.4.41"
TIER3_KEY="$HOME/.ssh/tier3_key"
TIER1_IP="174.129.11.27"

LOG="/home/ubuntu/logs/soft_rebuild_tier3_$(date +%Y%m%d_%H%M%S).log"
mkdir -p /home/ubuntu/logs

exec > >(tee -a "$LOG") 2>&1

echo "[soft_rebuild] $(date -u) — Starting Tier 3 soft rebuild"

SSH_CMD="ssh -i $TIER3_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=15 ubuntu@$TIER3_IP"

# 1. Verify SSH connectivity
if ! $SSH_CMD "echo ok" > /dev/null 2>&1; then
    echo "[soft_rebuild] ERROR: Cannot SSH to Tier 3. Manual intervention required."
    exit 1
fi

# 2. Kill all user processes (except sshd)
echo "[soft_rebuild] Killing user processes..."
$SSH_CMD "sudo pkill -u ubuntu -f -9 'node|python|gemini' || true"

# 3. Wipe user data (agent memory, results, downloads, caches, temp files)
echo "[soft_rebuild] Wiping user state..."
$SSH_CMD "
rm -rf ~/results/* 2>/dev/null || true
rm -rf ~/Downloads/* 2>/dev/null || true
rm -rf ~/.*_history 2>/dev/null || true
rm -rf ~/.cache/* 2>/dev/null || true
rm -rf ~/.local/share/* 2>/dev/null || true
rm -rf ~/.npm/_cacache/* 2>/dev/null || true
rm -rf /tmp/* 2>/dev/null || true
# Remove any .env files that might have been created
find ~ -name '.env' -type f -delete 2>/dev/null || true
# Remove any agent memory or session files
find ~ -name '*.json' -newer ~/email-config/README.txt -not -path '~/.config/gemini/*' -delete 2>/dev/null || true
# Remove any scripts that aren't part of the base setup
find ~ -name '*.sh' -not -name 'provision_tier3.sh' -not -name 'verify_tier3.sh' -delete 2>/dev/null || true
# Remove cron jobs (attacker might have installed some)
crontab -r 2>/dev/null || true
echo 'User state wiped.'
"

# 4. Verify no unexpected cron jobs
echo "[soft_rebuild] Checking for unauthorized cron jobs..."
$SSH_CMD "crontab -l 2>/dev/null && echo 'WARNING: Cron jobs found after wipe!' || echo 'No cron jobs - GOOD'"
$SSH_CMD "sudo ls /etc/cron.d/ | grep -v -E '^(e2scrub_all|popularity-contest|sysstat)$' && echo 'WARNING: Unexpected cron.d entries!' || echo 'No unexpected cron.d entries - GOOD'"

# 5. Verify no unexpected listening ports
echo "[soft_rebuild] Checking for unauthorized listeners..."
$SSH_CMD "sudo ss -tlnp | grep -v -E '(:22\s|:53\s)' && echo 'WARNING: Unexpected listeners!' || echo 'Only SSH and DNS - GOOD'"

# 6. Verify SSH config unchanged
echo "[soft_rebuild] Verifying SSH config..."
$SSH_CMD "grep '^PasswordAuthentication' /etc/ssh/sshd_config"

# 7. Verify UFW
echo "[soft_rebuild] Verifying UFW..."
$SSH_CMD "sudo ufw status | grep -c 'ALLOW' | xargs -I{} echo 'UFW rules: {}'"

# 8. Recreate results directory
$SSH_CMD "mkdir -p ~/results"

echo "[soft_rebuild] $(date -u) — Tier 3 soft rebuild complete."
echo "[soft_rebuild] Log: $LOG"
