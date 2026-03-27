#!/bin/bash
# verify_tier3.sh — Run on Tier 3 to verify configuration
echo "=== UFW Status ==="
sudo ufw status verbose

echo ""
echo "=== Listening Ports ==="
sudo ss -tlnp

echo ""
echo "=== Outbound Web Access ==="
curl -s -o /dev/null -w "HTTP %{http_code}" https://www.google.com && echo " - Outbound OK" || echo " - Outbound FAILED"

echo ""
echo "=== No Credentials Check ==="
ENV_COUNT=$(find /home/ubuntu -name '.env' -type f 2>/dev/null | wc -l)
SENSITIVE_COUNT=$(find /home/ubuntu -name '*.key' -o -name '*.pem' -o -name 'credentials*' -o -name 'vault*' 2>/dev/null | wc -l)
echo "  .env files: $ENV_COUNT"
echo "  Sensitive files: $SENSITIVE_COUNT"

echo ""
echo "=== Node.js ==="
node --version
npm --version

echo ""
echo "=== Disabled Services ==="
systemctl is-active snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null || echo "SSM Agent: inactive"
systemctl is-active apache2 2>/dev/null || echo "Apache: inactive"
systemctl is-active nginx 2>/dev/null || echo "Nginx: inactive"

echo ""
echo "=== No HTTP Servers ==="
HTTP_LISTEN=$(sudo ss -tlnp | grep -E ':80\b|:443\b|:8080\b' || true)
if [ -z "$HTTP_LISTEN" ]; then
    echo "No HTTP servers listening - GOOD"
else
    echo "WARNING: HTTP server found!"
    echo "$HTTP_LISTEN"
fi

echo ""
echo "=== SSH Config ==="
grep -E "^PasswordAuthentication|^PubkeyAuthentication" /etc/ssh/sshd_config

echo ""
echo "=== Disk Usage ==="
df -h /

echo ""
echo "=== VERIFICATION COMPLETE ==="
