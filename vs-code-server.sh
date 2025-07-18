#!/bin/bash

# VS Code Server Setup Script for Ubuntu 24.04
# This script installs VS Code CLI and sets up tunneling for remote connections
# Unlike code-server.sh which sets up web-based code-server, this creates a tunnel
# that can be accessed from other VS Code IDE instances remotely

set -e

# Function to print status messages
print_status() {
    echo "[INFO] $1"
}

print_success() {
    echo "[SUCCESS] $1"
}

print_warning() {
    echo "[WARNING] $1"
}

print_error() {
    echo "[ERROR] $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect architecture for Ubuntu 24.04
detect_arch() {
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64)
            echo "x64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        *)
            print_error "Unsupported architecture for Ubuntu 24.04: $arch"
            exit 1
            ;;
    esac
}

# Function to install VS Code CLI on Ubuntu 24.04
install_vscode_cli() {
    print_status "Installing VS Code CLI for Ubuntu 24.04..."

    # Add Microsoft GPG key and repository
    print_status "Adding Microsoft repository..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
    sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'

    # Update package list
    print_status "Updating package list..."
    sudo apt update

    # Install VS Code
    print_status "Installing VS Code..."
    sudo apt install -y code

    # Clean up
    rm -f packages.microsoft.gpg

    print_success "VS Code CLI installed successfully"
}

# Function to setup systemd service for tunnel
setup_tunnel_service() {
    local tunnel_name="$1"
    local service_name="vscode-tunnel"

    print_status "Setting up systemd service for VS Code tunnel..."

    # Determine the correct code binary path
    local code_path
    if command_exists code; then
        code_path=$(which code)
    else
        print_error "VS Code CLI not found in PATH"
        exit 1
    fi

    # Create systemd service file with improved configuration
    sudo tee "/etc/systemd/system/${service_name}.service" > /dev/null <<EOF
[Unit]
Description=VS Code Tunnel Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$(whoami)
Group=$(id -gn)
WorkingDirectory=$HOME
Environment=HOME=$HOME
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u)
ExecStart=${code_path} tunnel --name ${tunnel_name} --accept-server-license-terms --verbose
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30
Restart=always
RestartSec=15
StartLimitInterval=300
StartLimitBurst=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vscode-tunnel

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"

    print_success "Systemd service created and enabled"
}

# Function to handle authentication setup
setup_authentication() {
    local tunnel_name="$1"

    print_status "Setting up VS Code tunnel authentication..."
    print_warning "You will need to authenticate with GitHub/Microsoft account"

    # Check if already authenticated by trying to list tunnels
    if code tunnel user show >/dev/null 2>&1; then
        print_success "Already authenticated with VS Code tunnel service"
        return 0
    fi

    print_status "Starting authentication process..."
    print_status "This will show an authentication URL and device code"
    print_status "Complete the authentication in your browser, then the process will continue automatically"
    echo

    # Create a temporary script to handle the authentication
    local auth_script="/tmp/vscode_auth_$$"
    cat > "$auth_script" <<'EOF'
#!/bin/bash
# Temporary authentication script
exec code tunnel --name "$1" --accept-server-license-terms
EOF
    chmod +x "$auth_script"

    # Run authentication with timeout and proper signal handling
    print_status "Starting authentication (will timeout in 300 seconds)..."
    if timeout 300 "$auth_script" "$tunnel_name"; then
        print_success "Authentication completed successfully"
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            print_warning "Authentication timed out after 5 minutes"
        else
            print_warning "Authentication process completed (exit code: $exit_code)"
        fi
    fi

    # Clean up
    rm -f "$auth_script"

    # Verify authentication worked
    sleep 2
    if code tunnel user show >/dev/null 2>&1; then
        print_success "Authentication verification successful"
        return 0
    else
        print_error "Authentication verification failed"
        return 1
    fi
}

# Function to start tunnel service
start_tunnel_service() {
    local service_name="vscode-tunnel"

    print_status "Starting VS Code tunnel service..."
    sudo systemctl start "$service_name"

    # Wait a moment and check status
    sleep 3
    if sudo systemctl is-active --quiet "$service_name"; then
        print_success "VS Code tunnel service started successfully"
    else
        print_error "Failed to start VS Code tunnel service"
        print_status "Check service status with: sudo systemctl status $service_name"
        print_status "Check logs with: sudo journalctl -u $service_name -f"
        return 1
    fi
}

# Function to verify tunnel connectivity
verify_tunnel_connectivity() {
    local tunnel_name="$1"
    local service_name="vscode-tunnel"
    
    print_status "Verifying tunnel connectivity..."
    
    # Wait for service to fully start
    sleep 10
    
    # Check if tunnel is registered
    if code tunnel status >/dev/null 2>&1; then
        print_success "Tunnel is registered and active"
        
        # Try to list tunnels to verify connectivity
        print_status "Checking tunnel registration..."
        if timeout 30 code tunnel user show 2>/dev/null | grep -q "Logged in"; then
            print_success "Authentication verified - tunnel should be accessible"
        else
            print_warning "Authentication status unclear - check logs if connection issues persist"
        fi
    else
        print_warning "Tunnel status check failed - this may be normal during startup"
    fi
    
    # Check service logs for any immediate errors
    print_status "Checking recent service logs..."
    if sudo journalctl -u "$service_name" --since "1 minute ago" --no-pager -q | grep -i error; then
        print_warning "Found errors in service logs - check full logs with: sudo journalctl -u $service_name -f"
    else
        print_success "No immediate errors found in service logs"
    fi
}

# Function to show tunnel status and connection info
show_tunnel_info() {
    local tunnel_name="$1"
    local service_name="vscode-tunnel"

    print_success "VS Code Tunnel Setup Complete!"
    echo "=============================================="
    echo "Tunnel Name: $tunnel_name"
    echo "Service Name: $service_name"
    echo
    echo "To connect from another VS Code instance:"
    echo "1. Open VS Code on your local machine"
    echo "2. Install the 'Remote - Tunnels' extension"
    echo "3. Use Command Palette (Ctrl+Shift+P / Cmd+Shift+P)"
    echo "4. Run 'Remote-Tunnels: Connect to Tunnel'"
    echo "5. Select your tunnel: $tunnel_name"
    echo
    echo "Alternative connection methods:"
    echo "- Use vscode.dev in browser and connect to tunnel"
    echo "- Use VS Code Insiders with tunnel support"
    echo
    echo "Troubleshooting Connection Issues:"
    echo "- Wait 1-2 minutes after setup for tunnel to fully initialize"
    echo "- Check firewall settings (tunnel uses HTTPS/443)"
    echo "- Verify internet connectivity on both client and server"
    echo "- Try restarting the service: sudo systemctl restart $service_name"
    echo
    echo "Service Management Commands:"
    echo "- Check status: sudo systemctl status $service_name"
    echo "- View logs: sudo journalctl -u $service_name -f"
    echo "- Stop service: sudo systemctl stop $service_name"
    echo "- Start service: sudo systemctl start $service_name"
    echo "- Restart service: sudo systemctl restart $service_name"
    echo
    echo "Manual tunnel command (for debugging):"
    echo "code tunnel --name $tunnel_name --verbose"
    echo "=============================================="
}

# Function to check Ubuntu version
check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS version"
        exit 1
    fi
    
    local version_id
    version_id=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    
    if [[ "$version_id" != "24.04" ]]; then
        print_warning "This script is optimized for Ubuntu 24.04, detected: $version_id"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Main execution
main() {
    print_status "VS Code Server Setup for Ubuntu 24.04 Starting..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        exit 1
    fi
    
    # Check Ubuntu version
    check_ubuntu_version
    
    # Update system packages
    print_status "Updating system packages..."
    sudo apt update && sudo apt upgrade -y
    
    # Install required dependencies
    print_status "Installing dependencies..."
    sudo apt install -y curl wget gpg
    
    # Check if VS Code CLI is already installed
    if command_exists code; then
        print_warning "VS Code is already installed"
        code --version
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_vscode_cli
        fi
    else
        install_vscode_cli
    fi
    
    # Verify installation
    if ! command_exists code; then
        print_error "VS Code installation failed"
        exit 1
    fi
    
    print_success "VS Code CLI is ready"
    code --version
    
    # Prompt for tunnel name
    while true; do
        read -p "Enter a name for your VS Code tunnel [$(hostname)-tunnel]: " TUNNEL_NAME
        TUNNEL_NAME="${TUNNEL_NAME:-$(hostname)-tunnel}"
        # Validate tunnel name (alphanumeric and hyphens only)
        if [[ "$TUNNEL_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
            break
        else
            print_error "Tunnel name can only contain letters, numbers, and hyphens. Please try again."
        fi
    done

    print_status "Using tunnel name: $TUNNEL_NAME"

    # Setup systemd service
    setup_tunnel_service "$TUNNEL_NAME"

    # Always run authentication setup before starting the service
    if setup_authentication "$TUNNEL_NAME"; then
        print_status "Authentication complete. Starting the tunnel service..."
        start_tunnel_service
        
        # Verify tunnel connectivity
        verify_tunnel_connectivity "$TUNNEL_NAME"
    else
        print_error "Authentication failed. Please try running the script again."
        exit 1
    fi

    # Show final information
    show_tunnel_info "$TUNNEL_NAME"
}

# Run main function
main "$@"
