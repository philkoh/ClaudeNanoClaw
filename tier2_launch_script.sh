#!/bin/bash
# Tier 2 (OpenClaw Semi-Protected) Launch/Provisioning Script
# This runs as root via Lightsail user-data on first boot
set -e
exec > /var/log/tier2_provision.log 2>&1
echo "=== Tier 2 Provisioning Started: $(date) ==="

TIER1_IP="174.129.11.27"
ADMIN_IP="100.36.24.89"
TIER1_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJe1ORLhNYQ7r8guXiCOH2cGEsVzc5N98hap+Utw7ZWN tier1-to-tier2"

# --- SSH Hardening ---
echo 'PasswordAuthentication no' > /etc/ssh/sshd_config.d/no-password.conf
systemctl reload ssh

# Add Tier 1's dedicated key to authorized_keys
su - ubuntu -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
echo "$TIER1_PUBKEY" >> /home/ubuntu/.ssh/authorized_keys
chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
chmod 600 /home/ubuntu/.ssh/authorized_keys

echo "=== SSH hardened, Tier 1 key added ==="

# --- Install packages ---
apt-get update -qq
apt-get install -y -qq docker.io squid dnsutils > /dev/null 2>&1
usermod -aG docker ubuntu
echo "=== Packages installed ==="

# --- Disable unnecessary services ---
for svc in amazon-ssm-agent snap.amazon-ssm-agent.amazon-ssm-agent ModemManager snapd; do
  systemctl disable --now "$svc" 2>/dev/null || true
done
for svc in apache2 nginx lighttpd; do
  systemctl disable --now "$svc" 2>/dev/null || true
done
echo "=== Unnecessary services disabled ==="

# --- Configure Squid ---
cp /etc/squid/squid.conf /etc/squid/squid.conf.orig
touch /etc/squid/whitelist.txt
chown proxy:proxy /etc/squid/whitelist.txt

cat > /etc/squid/squid.conf << 'SQUIDCONF'
# Squid configuration for Tier 2 - CONNECT-based domain filtering
# Listens on localhost only
http_port 127.0.0.1:3128

# ACL definitions
acl localnet src 127.0.0.1/32
acl SSL_ports port 443
acl CONNECT method CONNECT

# Whitelist: domains allowed for HTTPS CONNECT (dynamically managed)
acl allowed_domains dstdomain "/etc/squid/whitelist.txt"

# Always allow Anthropic API
acl anthropic_api dstdomain api.anthropic.com

# Deny non-SSL ports for CONNECT
http_access deny CONNECT !SSL_ports

# Allow CONNECT to whitelisted domains and Anthropic API
http_access allow CONNECT anthropic_api
http_access allow CONNECT allowed_domains

# Allow local connections for non-CONNECT
http_access allow localnet anthropic_api
http_access allow localnet allowed_domains

# Default deny everything else
http_access deny all

# Logging
access_log daemon:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log

# No caching - just proxying
cache deny all

# Timeouts
connect_timeout 30 seconds
read_timeout 60 seconds

# Security - hide proxy identity
via off
forwarded_for delete
SQUIDCONF

systemctl restart squid
systemctl enable squid
echo "=== Squid configured ==="

# --- Create /opt/scripts ---
mkdir -p /opt/scripts

# --- Resolve Anthropic API IPs ---
ANTHROPIC_IPS=$(dig +short api.anthropic.com | grep -E '^[0-9]' | sort -u)
echo "$ANTHROPIC_IPS" > /opt/scripts/anthropic_ips.txt
echo "Anthropic IPs: $ANTHROPIC_IPS"

# --- Create open_portal.sh ---
cat > /opt/scripts/open_portal.sh << 'SCRIPTEOF'
#!/bin/bash
# open_portal.sh - Called by Tier 1 via SSH to open egress for a specific domain
# Usage: open_portal.sh <domain> [--cloudflare]
set -e

DOMAIN="$1"
if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <domain> [--cloudflare]"
  exit 1
fi

echo "[open_portal] Opening egress for: $DOMAIN"

# Resolve current IPs for the domain
IPS=$(dig +short "$DOMAIN" | grep -E '^[0-9]')
if [ -z "$IPS" ]; then
  echo "[open_portal] WARNING: Could not resolve IPs for $DOMAIN"
  exit 1
fi

# Add UFW rules for each resolved IP
for IP in $IPS; do
  sudo ufw allow out to "$IP" port 443 comment "portal:$DOMAIN"
  echo "[open_portal] Allowed outbound to $IP:443 ($DOMAIN)"
done

# Add domain to Squid whitelist
if ! grep -qxF "$DOMAIN" /etc/squid/whitelist.txt 2>/dev/null; then
  echo "$DOMAIN" | sudo tee -a /etc/squid/whitelist.txt > /dev/null
  echo "[open_portal] Added $DOMAIN to Squid whitelist"
fi

# Handle Cloudflare-proxied domains
if [ "$2" == "--cloudflare" ]; then
  echo "[open_portal] Adding Cloudflare IP ranges..."
  CF_RANGES=$(curl -s https://www.cloudflare.com/ips-v4 2>/dev/null || echo "")
  if [ -z "$CF_RANGES" ]; then
    # Fallback: known Cloudflare IPv4 ranges
    CF_RANGES="173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22"
  fi
  for CIDR in $CF_RANGES; do
    sudo ufw allow out to "$CIDR" port 443 comment "cloudflare:$DOMAIN"
  done
  echo "[open_portal] Cloudflare ranges added"
fi

# Reload Squid to pick up whitelist changes
sudo squid -k reconfigure 2>/dev/null || sudo systemctl reload squid 2>/dev/null || true
echo "[open_portal] Portal opened for $DOMAIN"
SCRIPTEOF
chmod +x /opt/scripts/open_portal.sh

# --- Create close_portal.sh ---
cat > /opt/scripts/close_portal.sh << 'SCRIPTEOF'
#!/bin/bash
# close_portal.sh - Called by Tier 1 after task completion to reset firewall
# Resets UFW to default deny, keeping SSH from Tier 1 and Anthropic API access
set -e

TIER1_IP="174.129.11.27"

echo "[close_portal] Resetting firewall to default deny..."

# Reset UFW completely
sudo ufw --force reset

# Re-apply baseline rules
sudo ufw default deny incoming
sudo ufw default deny outgoing

# SSH from Tier 1 only
sudo ufw allow in from "$TIER1_IP" to any port 22 comment "SSH from Tier 1"

# DNS for local resolution
sudo ufw allow out to 127.0.0.53 port 53 comment "DNS stub resolver"

# Loopback (needed for Squid)
sudo ufw allow in on lo
sudo ufw allow out on lo

# Anthropic API
ANTHROPIC_IPS=$(dig +short api.anthropic.com | grep -E '^[0-9]' | sort -u)
for IP in $ANTHROPIC_IPS; do
  sudo ufw allow out to "$IP" port 443 comment "Anthropic API"
done

# Enable UFW
sudo ufw --force enable

# Empty Squid whitelist
sudo truncate -s 0 /etc/squid/whitelist.txt

# Reload Squid
sudo squid -k reconfigure 2>/dev/null || sudo systemctl reload squid 2>/dev/null || true

echo "[close_portal] Firewall reset to baseline. All portal access closed."
sudo ufw status numbered
SCRIPTEOF
chmod +x /opt/scripts/close_portal.sh

echo "=== Scripts created ==="

# --- Configure UFW ---
ufw --force reset
ufw default deny incoming
ufw default deny outgoing

# SSH from Tier 1
ufw allow in from "$TIER1_IP" to any port 22 comment "SSH from Tier 1"

# Temporary: SSH from admin IP (remove after setup verified)
ufw allow in from "$ADMIN_IP" to any port 22 comment "temp:admin"

# DNS for local resolution
ufw allow out to 127.0.0.53 port 53 comment "DNS stub resolver"

# Loopback for Squid
ufw allow in on lo
ufw allow out on lo

# Anthropic API outbound
for IP in $ANTHROPIC_IPS; do
  ufw allow out to "$IP" port 443 comment "Anthropic API"
done

ufw --force enable
echo "=== UFW configured ==="
ufw status verbose

echo "=== Tier 2 Provisioning Complete: $(date) ==="
