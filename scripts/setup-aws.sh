#!/bin/bash
set -eo pipefail

# Load configuration from external file
CONFIG_FILE="config.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    # Default values if no config file exists
    DUCKDNS_DOMAIN="joster"
    DUCKDNS_TOKEN="your-token-here"
    ADMIN_EMAIL="your-email@example.com"
fi

# Backup existing nginx config if it exists
if [ -f /etc/nginx/nginx.conf ]; then
    echo "[INFO] Backing up existing nginx configuration..."
    sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
fi

# ==============================
# 1. Update & install packages
# ==============================
echo "[INFO] Updating system and installing packages..."
sudo dnf -y update

# Install required packages
sudo dnf -y install nginx certbot python3-certbot-nginx firewalld cronie curl-minimal

# ==============================
# 2. Start & enable services
# ==============================
echo "[INFO] Starting NGINX, Firewalld, and Cron..."
sudo systemctl enable --now nginx
sudo systemctl enable --now firewalld
sudo systemctl enable --now crond

# ==============================
# 3. Firewall configuration
# ==============================
echo "[INFO] Configuring firewall rules..."
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload

# ==============================
# 4. DuckDNS update script
# ==============================
echo "[INFO] Setting up DuckDNS auto-update..."
mkdir -p ~/duckdns
cat <<EOL > ~/duckdns/update.sh
#!/bin/bash
if command -v curl &>/dev/null; then
    curl -k -s "https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip="
elif command -v wget &>/dev/null; then
    wget -qO- "https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip="
else
    echo "[ERROR] Neither curl nor wget is installed."
fi
EOL
chmod +x ~/duckdns/update.sh

# Add cron job (runs every 5 minutes)
(crontab -l 2>/dev/null; echo "*/5 * * * * ~/duckdns/update.sh >/dev/null 2>&1") | crontab -

# ==============================
# 5. Certbot SSL creation
# ==============================
echo "[INFO] Requesting SSL certificate from Let's Encrypt..."
sudo certbot --nginx \
  -d "$DUCKDNS_DOMAIN.duckdns.org" \
  --non-interactive \
  --agree-tos \
  -m "$ADMIN_EMAIL" \
  --redirect

# ==============================
# 6. Done
# ==============================
echo "[SUCCESS] Setup complete!"
echo "Visit: https://$DUCKDNS_DOMAIN.duckdns.org"
echo "NGINX root dir: /usr/share/nginx/html"

