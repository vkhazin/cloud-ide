#!/bin/bash

# Enhanced Desktop Setup Script with Error Handling and SSL/Nginx Support
# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/desktop_setup.log"
DOMAIN_NAME=""
NGINX_USER=""
NGINX_PASS=""
GUACAMOLE_PORT=8080
RDP_PORT=3389

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            ;;
    esac
}

# Error handler function
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Installation failed. Check log file: $LOG_FILE"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if port is available
check_port_available() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        return 1
    else
        return 0
    fi
}

# Find next available port
find_available_port() {
    local start_port=$1
    local port=$start_port
    
    while ! check_port_available "$port"; do
        log "WARN" "Port $port is in use, trying next port..."
        ((port++))
        if [ $port -gt $((start_port + 100)) ]; then
            error_exit "Could not find available port after checking 100 ports starting from $start_port"
        fi
    done
    
    echo "$port"
}

# Pre-flight checks
preflight_checks() {
    log "INFO" "Starting pre-flight checks..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        error_exit "This script should not be run as root. Please run as a regular user with sudo privileges."
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        log "INFO" "Testing sudo access..."
        sudo -v || error_exit "This script requires sudo privileges"
    fi
    
    # Check internet connectivity
    log "INFO" "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        error_exit "No internet connectivity detected"
    fi
    
    # Check available disk space (require at least 2GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 2000000 ]; then
        error_exit "Insufficient disk space. At least 2GB required."
    fi
    
    # Check if user has a password set (required for RDP)
    if ! passwd -S "$USER" | grep -q "P"; then
        log "WARN" "User $USER does not have a password set. RDP requires a password."
        read -p "Would you like to set a password now? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            passwd || error_exit "Failed to set user password"
        else
            log "WARN" "Continuing without password. You'll need to set one manually for RDP to work."
        fi
    fi
    
    log "INFO" "Pre-flight checks completed successfully"
}

# Get user input for domain and authentication
get_user_input() {
    log "INFO" "Gathering configuration information..."
    
    # Get domain name
    while [[ -z "$DOMAIN_NAME" ]]; do
        read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
        if [[ ! "$DOMAIN_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
            log "WARN" "Invalid domain name format"
            DOMAIN_NAME=""
        fi
    done
    
    # Check DNS resolution
    log "INFO" "Checking DNS resolution for $DOMAIN_NAME..."
    local current_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)
    local resolved_ip=$(dig +short "$DOMAIN_NAME" | head -n1)
    
    if [[ -z "$resolved_ip" ]]; then
        log "WARN" "Domain $DOMAIN_NAME does not resolve to any IP"
        read -p "Continue anyway? (y/n): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    elif [[ "$resolved_ip" != "$current_ip" ]]; then
        log "WARN" "Domain $DOMAIN_NAME resolves to $resolved_ip but server IP is $current_ip"
        read -p "Continue anyway? (y/n): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log "INFO" "DNS resolution confirmed: $DOMAIN_NAME -> $current_ip"
    fi
    
    # Get nginx authentication credentials
    while [[ -z "$NGINX_USER" ]]; do
        read -p "Enter username for nginx basic authentication: " NGINX_USER
    done
    
    while [[ -z "$NGINX_PASS" ]]; do
        read -s -p "Enter password for nginx basic authentication: " NGINX_PASS
        echo
        if [[ ${#NGINX_PASS} -lt 8 ]]; then
            log "WARN" "Password should be at least 8 characters long"
            NGINX_PASS=""
        fi
    done
    
    log "INFO" "Configuration complete"
}

# System update function
system_update() {
    log "INFO" "Updating system packages..."
    
    # Update package lists
    sudo apt update || error_exit "Failed to update package lists"
    
    # Upgrade packages
    sudo apt upgrade -y || error_exit "Failed to upgrade packages"
    
    log "INFO" "System update completed"
}

# Desktop setup function
desktop_setup() {
    log "INFO" "Installing XFCE desktop environment..."
    
    # Install XFCE and goodies
    sudo apt install -y xfce4 xfce4-goodies || error_exit "Failed to install XFCE desktop"
    
    # Configure XFCE for the user
    echo "startxfce4" > ~/.xsession
    
    log "INFO" "Desktop setup completed"
}

# Remote desktop setup function
remote_desktop_setup() {
    log "INFO" "Setting up remote desktop (XRDP)..."
    
    # Find available RDP port
    RDP_PORT=$(find_available_port $RDP_PORT)
    log "INFO" "Using RDP port: $RDP_PORT"
    
    # Install XRDP
    sudo apt install -y xrdp || error_exit "Failed to install XRDP"
    
    # Configure XRDP port if not default
    if [[ $RDP_PORT -ne 3389 ]]; then
        sudo sed -i "s/port=3389/port=$RDP_PORT/" /etc/xrdp/xrdp.ini
    fi
    
    # Enable and start XRDP
    sudo systemctl enable xrdp || error_exit "Failed to enable XRDP service"
    sudo systemctl restart xrdp || error_exit "Failed to start XRDP service"
    
    # Verify XRDP is running
    if ! sudo systemctl is-active --quiet xrdp; then
        error_exit "XRDP service failed to start"
    fi
    
    log "INFO" "Remote desktop setup completed on port $RDP_PORT"
}

# Docker and Guacamole setup function
guacamole_setup() {
    log "INFO" "Setting up Docker and Guacamole..."
    
    # Install Docker and Docker Compose
    sudo apt install -y docker.io docker-compose || error_exit "Failed to install Docker"
    
    # Enable and start Docker
    sudo systemctl enable docker || error_exit "Failed to enable Docker service"
    sudo systemctl start docker || error_exit "Failed to start Docker service"
    
    # Wait for Docker to be fully ready
    sleep 5
    
    # Add user to docker group
    sudo usermod -aG docker "$USER" || error_exit "Failed to add user to docker group"
    
    # Find available Guacamole port
    GUACAMOLE_PORT=$(find_available_port $GUACAMOLE_PORT)
    log "INFO" "Using Guacamole port: $GUACAMOLE_PORT"
    
    # Create Guacamole directory
    local guac_dir="$HOME/guacamole"
    mkdir -p "$guac_dir" || error_exit "Failed to create Guacamole directory"
    cd "$guac_dir"
    
    # Create user-mapping.xml
    cat <<EOF > user-mapping.xml
<user-mapping>
    <authorize username="$USER" password="$USER">
        <connection name="Ubuntu XFCE">
            <protocol>rdp</protocol>
            <param name="hostname">localhost</param>
            <param name="port">$RDP_PORT</param>
            <param name="username">$USER</param>
            <param name="ignore-cert">true</param>
        </connection>
    </authorize>
</user-mapping>
EOF
    
    # Create docker-compose.yml
    cat <<EOF > docker-compose.yml
version: '3'
services:
  guacd:
    image: guacamole/guacd
    container_name: guacd
    restart: always

  guacamole:
    image: guacamole/guacamole
    container_name: guacamole
    restart: always
    ports:
      - "$GUACAMOLE_PORT:8080"
    volumes:
      - ./user-mapping.xml:/etc/guacamole/user-mapping.xml:ro
    environment:
      GUACAMOLE_HOME: /etc/guacamole
    depends_on:
      - guacd
    extra_hosts:
      - "host.docker.internal:host-gateway"
EOF
    
    # Use sudo to run docker-compose since user group membership won't be active until next login
    log "INFO" "Starting Guacamole containers with sudo..."
    sudo docker-compose up -d || error_exit "Failed to start Guacamole containers"
    
    # Verify containers are running
    sleep 10
    if ! sudo docker ps | grep -q guacamole; then
        error_exit "Guacamole container failed to start"
    fi
    
    # Set proper ownership of guacamole directory
    sudo chown -R "$USER:$USER" "$guac_dir"
    
    log "INFO" "Guacamole setup completed on port $GUACAMOLE_PORT"
}

# Nginx setup function
nginx_setup() {
    log "INFO" "Setting up Nginx reverse proxy..."
    
    # Install Nginx
    sudo apt install -y nginx apache2-utils || error_exit "Failed to install Nginx"
    
    # Create htpasswd file
    sudo htpasswd -bc /etc/nginx/.htpasswd "$NGINX_USER" "$NGINX_PASS" || error_exit "Failed to create htpasswd file"
    
    # Create Nginx configuration
    sudo tee /etc/nginx/sites-available/"$DOMAIN_NAME" > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN_NAME;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    location /desktop {
        auth_basic "Restricted Access";
        auth_basic_user_file /etc/nginx/.htpasswd;
        
        proxy_pass http://localhost:$GUACAMOLE_PORT/guacamole;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
        proxy_cookie_path /guacamole /desktop;
    }
    
    location / {
        return 404;
    }
}
EOF
    
    # Enable the site
    sudo ln -sf /etc/nginx/sites-available/"$DOMAIN_NAME" /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Test Nginx configuration
    sudo nginx -t || error_exit "Nginx configuration test failed"
    
    log "INFO" "Nginx setup completed"
}

# Let's Encrypt setup function
letsencrypt_setup() {
    log "INFO" "Setting up Let's Encrypt SSL certificate..."
    
    # Install Certbot
    sudo apt install -y certbot python3-certbot-nginx || error_exit "Failed to install Certbot"
    
    # Stop Nginx temporarily for standalone certificate generation
    sudo systemctl stop nginx
    
    # Generate certificate
    sudo certbot certonly --standalone -d "$DOMAIN_NAME" --non-interactive --agree-tos --email "admin@$DOMAIN_NAME" || error_exit "Failed to generate SSL certificate"
    
    # Start Nginx
    sudo systemctl start nginx || error_exit "Failed to start Nginx"
    sudo systemctl enable nginx || error_exit "Failed to enable Nginx"
    
    # Setup auto-renewal
    sudo crontab -l 2>/dev/null | { cat; echo "0 12 * * * /usr/bin/certbot renew --quiet"; } | sudo crontab -
    
    log "INFO" "Let's Encrypt setup completed"
}

# Main execution function
main() {
    log "INFO" "Starting desktop setup script..."
    log "INFO" "Log file: $LOG_FILE"
    
    preflight_checks
    get_user_input
    system_update
    desktop_setup
    remote_desktop_setup
    guacamole_setup
    letsencrypt_setup
    nginx_setup
    
    log "INFO" "Setup completed successfully!"
    log "INFO" "Access your desktop at: https://$DOMAIN_NAME/desktop"
    log "INFO" "Username: $NGINX_USER"
    log "INFO" "Guacamole is running on port: $GUACAMOLE_PORT"
    log "INFO" "RDP is running on port: $RDP_PORT"
    log "INFO" ""
    log "INFO" "Important notes:"
    log "INFO" "1. You may need to logout and login again for docker group membership to take effect"
    log "INFO" "2. Ensure your firewall allows traffic on ports 80, 443, and $RDP_PORT"
    log "INFO" "3. The SSL certificate will auto-renew via crontab"
    log "INFO" "4. Check the log file for detailed information: $LOG_FILE"
}

# Trap errors and cleanup
trap 'error_exit "Script interrupted"' INT TERM

# Run main function
main "$@"
