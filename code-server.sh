#!/bin/bash

# Instructions for Ubuntu Server 24.04
# Launch a VM with ports 22, 80, 443 accessible from the internet
# User a dns setting to point to public IP of the VM
# Login to the VM using ssh
# Execute the command below
# bash <(curl -fsSL https://gist.githubusercontent.com/vkhazin/de15691155f54739c572d29bbb47b890/raw)
# Access using a web-browser and the url specified during execution of shell script

set -e

# Function to generate random string for secrets
generate_secret() {
  openssl rand -hex 32
}

# Prompt for domain and validate resolution
while true; do
  read -rp "Enter your domain name (e.g., code.example.com) [cloud-ide.example.com]: " DOMAIN
  DOMAIN="${DOMAIN:-cloud-ide.example.com}"
  DOMAIN_IP=$(getent hosts "$DOMAIN" | awk '{ print $1 }')
  PUBLIC_IP=$(curl -s https://ipinfo.io/ip)

  if [ -z "$DOMAIN_IP" ]; then
    echo "Error: Could not resolve domain '$DOMAIN'. Please check your DNS settings."
  elif [ "$DOMAIN_IP" != "$PUBLIC_IP" ]; then
    echo "Error: Domain '$DOMAIN' resolves to $DOMAIN_IP, but this server's public IP is $PUBLIC_IP."
    echo "Please update your DNS A record to point to this server."
  else
    echo "Domain resolves correctly to this server's public IP ($PUBLIC_IP)."
    break
  fi
done

# Prompt for username and password for NGINX basic auth
read -rp "Enter the username for code-server access [ubuntu]: " NGINX_USER
NGINX_USER="${NGINX_USER:-ubuntu}"
while true; do
  read -rsp "Enter password for code-server user: " NGINX_PASS1; echo
  read -rsp "Confirm password: " NGINX_PASS2; echo
  if [ "$NGINX_PASS1" != "$NGINX_PASS2" ]; then
    echo "Passwords do not match. Please try again."
    continue
  fi
  if [ -z "$NGINX_PASS1" ]; then
    echo "Password cannot be empty. Please try again."
    continue
  fi
  if [[ ${#NGINX_PASS1} -lt 12 ]]; then
    echo "Password must be at least 12 characters long."
    continue
  fi
  if ! [[ "$NGINX_PASS1" =~ [a-z] ]]; then
    echo "Password must contain at least one lowercase letter."
    continue
  fi
  if ! [[ "$NGINX_PASS1" =~ [A-Z] ]]; then
    echo "Password must contain at least one uppercase letter."
    continue
  fi
  if ! [[ "$NGINX_PASS1" =~ [0-9] ]]; then
    echo "Password must contain at least one number."
    continue
  fi
  if ! [[ "$NGINX_PASS1" =~ [^a-zA-Z0-9] ]]; then
    echo "Password must contain at least one special character."
    continue
  fi
  echo "Password confirmed."
  break
done

# Update system
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

# Install required packages (no GUI)
sudo apt install -y nginx curl certbot python3-certbot-nginx wget

# Install code-server using the official installer
if ! command -v code-server &> /dev/null; then
  echo "Installing code-server using official installer..."
  curl -fsSL https://code-server.dev/install.sh | sh
else
  echo "code-server is already installed."
fi

# Create code-server config file with NO auth
echo "Configuring code-server for no authentication..."
mkdir -p "$HOME/.config/code-server"
cat > "$HOME/.config/code-server/config.yaml" <<EOF
bind-addr: 127.0.0.1:8080
auth: none
cert: false
EOF

# Create code-server systemd service
USER_NAME=$(whoami)
echo "Creating code-server service..."
sudo tee /etc/systemd/system/code-server.service > /dev/null <<EOF
[Unit]
Description=code-server
After=network.target

[Service]
Type=exec
ExecStart=/usr/bin/code-server
Restart=always
User=$USER_NAME
Environment=HOME=$HOME

[Install]
WantedBy=multi-user.target
EOF

# Install apache2-utils for htpasswd
sudo apt install -y apache2-utils

# Create htpasswd file for NGINX basic auth
sudo htpasswd -bc /etc/nginx/.htpasswd "$NGINX_USER" "$NGINX_PASS1"

# Add WebSocket upgrade mapping to nginx main configuration
echo "Adding WebSocket upgrade mapping to nginx configuration..."
sudo tee /etc/nginx/conf.d/websocket-upgrade.conf > /dev/null <<EOF
# WebSocket upgrade mapping
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}
EOF

# Configure NGINX reverse proxy (initially only HTTP for Certbot)
NGINX_CONF="/etc/nginx/sites-available/code-gateway"
echo "Creating initial NGINX configuration (HTTP only for Certbot)..."
sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    
    # Security headers (removed X-Frame-Options DENY)
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_http_version 1.1;
        
        # Timeout settings for WebSocket connections
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 60;
        
        # Buffer settings
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_redirect off;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

# Remove default nginx site if it exists
if [ -f /etc/nginx/sites-enabled/default ]; then
    echo "Removing default nginx site..."
    sudo rm /etc/nginx/sites-enabled/default
fi

# Test nginx configuration and reload
echo "Testing nginx configuration..."
if sudo nginx -t; then
    echo "Nginx configuration is valid. Reloading..."
    sudo systemctl reload nginx
else
    echo "ERROR: Nginx configuration test failed!"
    exit 1
fi

# Obtain Let's Encrypt certificate
if [ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
  echo "Obtaining Let's Encrypt certificate..."
  sudo certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m admin@${DOMAIN}
else
  echo "Renewing Let's Encrypt certificate if needed..."
  sudo certbot renew --quiet
fi

# Now write the full HTTP+HTTPS config
echo "Creating final NGINX configuration with HTTPS support..."
sudo tee "$NGINX_CONF" > /dev/null <<EOF
# HTTP server - redirect to HTTPS
server {
    listen 80;
    server_name ${DOMAIN};
    
    # Allow Let's Encrypt challenges
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
# HTTPS server
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    # Security headers (removed X-Frame-Options DENY)
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    # Basic authentication
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    
    # Main proxy location
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_http_version 1.1;
        
        # Timeout settings for WebSocket connections
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 60;
        
        # Buffer settings
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_redirect off;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Test final nginx configuration and reload
echo "Testing final nginx configuration..."
if sudo nginx -t; then
    echo "Final nginx configuration is valid. Reloading..."
    sudo systemctl reload nginx
else
    echo "ERROR: Final nginx configuration test failed!"
    echo "Check nginx error logs with: sudo journalctl -u nginx"
    exit 1
fi

# Enable and start services
sudo systemctl daemon-reload
sudo systemctl enable code-server
sudo systemctl start code-server
sudo systemctl restart nginx

# Wait for nginx to start
sleep 3

# Test if code-server is listening on localhost:8080
if curl -sSf http://127.0.0.1:8080 > /dev/null; then
  echo "code-server is running and listening on 127.0.0.1:8080."
else
  echo "ERROR: code-server is NOT listening on 127.0.0.1:8080! Check the systemd service logs with:"
  echo "  sudo journalctl -u code-server"
fi

cat <<EOM
==============================================
Setup Complete!
==============================================
Access URL:
- code-server: https://${DOMAIN}/
Authentication: Username '${NGINX_USER}' (password set during setup, via NGINX basic auth)
==============================================
EOM