#!/bin/bash

# VS Code Server Uninstall Script for Ubuntu 24.04
# This script removes all components installed by vs-code-server.sh
# Including VS Code CLI, systemd service, repositories, and configuration files

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

# Function to check if service exists
service_exists() {
    systemctl list-unit-files | grep -q "^$1"
}

# Function to stop and remove systemd service
remove_tunnel_service() {
    local service_name="vscode-tunnel"
    
    print_status "Removing VS Code tunnel systemd service..."
    
    if service_exists "$service_name"; then
        # Stop the service if it's running
        if sudo systemctl is-active --quiet "$service_name"; then
            print_status "Stopping $service_name service..."
            sudo systemctl stop "$service_name"
        fi
        
        # Disable the service
        if sudo systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
            print_status "Disabling $service_name service..."
            sudo systemctl disable "$service_name"
        fi
        
        # Remove the service file
        if [[ -f "/etc/systemd/system/${service_name}.service" ]]; then
            print_status "Removing service file..."
            sudo rm -f "/etc/systemd/system/${service_name}.service"
        fi
        
        # Reload systemd
        sudo systemctl daemon-reload
        sudo systemctl reset-failed 2>/dev/null || true
        
        print_success "Systemd service removed successfully"
    else
        print_warning "VS Code tunnel service not found"
    fi
}

# Function to remove VS Code and related packages
remove_vscode() {
    print_status "Removing VS Code and related packages..."
    
    if command_exists code; then
        # Remove VS Code package
        print_status "Uninstalling VS Code package..."
        sudo apt remove --purge -y code
        
        # Remove any leftover dependencies
        sudo apt autoremove -y
        
        print_success "VS Code package removed"
    else
        print_warning "VS Code not found in system"
    fi
}

# Function to remove Microsoft repository and GPG key
remove_microsoft_repo() {
    print_status "Removing Microsoft repository and GPG key..."
    
    # Remove repository file
    if [[ -f "/etc/apt/sources.list.d/vscode.list" ]]; then
        print_status "Removing VS Code repository..."
        sudo rm -f "/etc/apt/sources.list.d/vscode.list"
        print_success "VS Code repository removed"
    else
        print_warning "VS Code repository file not found"
    fi
    
    # Remove GPG key
    if [[ -f "/etc/apt/trusted.gpg.d/packages.microsoft.gpg" ]]; then
        print_status "Removing Microsoft GPG key..."
        sudo rm -f "/etc/apt/trusted.gpg.d/packages.microsoft.gpg"
        print_success "Microsoft GPG key removed"
    else
        print_warning "Microsoft GPG key not found"
    fi
    
    # Update package list
    print_status "Updating package list..."
    sudo apt update
}

# Function to remove VS Code user data and configuration
remove_user_data() {
    print_status "Removing VS Code user data and configuration..."
    
    local removed_items=()
    
    # Remove VS Code user data directory
    if [[ -d "$HOME/.vscode" ]]; then
        rm -rf "$HOME/.vscode"
        removed_items+=("VS Code user settings")
    fi
    
    # Remove VS Code CLI data directory
    if [[ -d "$HOME/.vscode-cli" ]]; then
        rm -rf "$HOME/.vscode-cli"
        removed_items+=("VS Code CLI data")
    fi
    
    # Remove VS Code server data directory
    if [[ -d "$HOME/.vscode-server" ]]; then
        rm -rf "$HOME/.vscode-server"
        removed_items+=("VS Code server data")
    fi
    
    # Remove VS Code tunnel authentication data
    if [[ -d "$HOME/.config/Code" ]]; then
        rm -rf "$HOME/.config/Code"
        removed_items+=("VS Code configuration")
    fi
    
    # Remove any tunnel-related cache
    if [[ -d "$HOME/.cache/vscode-cli" ]]; then
        rm -rf "$HOME/.cache/vscode-cli"
        removed_items+=("VS Code CLI cache")
    fi
    
    if [[ ${#removed_items[@]} -gt 0 ]]; then
        print_success "Removed user data: ${removed_items[*]}"
    else
        print_warning "No VS Code user data found to remove"
    fi
}

# Function to clean up any remaining processes
cleanup_processes() {
    print_status "Checking for running VS Code processes..."
    
    # Kill any running code processes
    if pgrep -f "code.*tunnel" >/dev/null; then
        print_status "Stopping VS Code tunnel processes..."
        pkill -f "code.*tunnel" || true
        sleep 2
    fi
    
    # Kill any remaining code processes
    if pgrep -x "code" >/dev/null; then
        print_warning "Found running VS Code processes. Stopping them..."
        pkill -x "code" || true
        sleep 2
    fi
    
    print_success "Process cleanup completed"
}

# Function to remove temporary files
cleanup_temp_files() {
    print_status "Cleaning up temporary files..."
    
    # Remove any temporary authentication scripts
    rm -f /tmp/vscode_auth_* 2>/dev/null || true
    
    # Remove any downloaded GPG files
    rm -f packages.microsoft.gpg 2>/dev/null || true
    
    print_success "Temporary files cleaned up"
}

# Function to show what will be removed
show_removal_plan() {
    echo "=============================================="
    echo "VS Code Server Uninstall Plan"
    echo "=============================================="
    echo "The following components will be removed:"
    echo
    
    if service_exists "vscode-tunnel"; then
        echo "✓ VS Code tunnel systemd service"
    fi
    
    if command_exists code; then
        echo "✓ VS Code CLI package"
    fi
    
    if [[ -f "/etc/apt/sources.list.d/vscode.list" ]]; then
        echo "✓ Microsoft VS Code repository"
    fi
    
    if [[ -f "/etc/apt/trusted.gpg.d/packages.microsoft.gpg" ]]; then
        echo "✓ Microsoft GPG key"
    fi
    
    local user_data_found=false
    if [[ -d "$HOME/.vscode" ]] || [[ -d "$HOME/.vscode-cli" ]] || [[ -d "$HOME/.vscode-server" ]] || [[ -d "$HOME/.config/Code" ]]; then
        echo "✓ VS Code user data and configuration"
        user_data_found=true
    fi
    
    echo
    if [[ "$user_data_found" == "true" ]]; then
        print_warning "This will remove ALL VS Code settings, extensions, and tunnel authentication!"
        print_warning "Make sure to backup any important VS Code configuration before proceeding."
        echo
    fi
    
    echo "=============================================="
}

# Function to confirm removal
confirm_removal() {
    echo
    read -p "Do you want to proceed with the uninstallation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Uninstallation cancelled by user"
        exit 0
    fi
    echo
}

# Main execution
main() {
    print_status "VS Code Server Uninstall Script Starting..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        print_error "Run as the same user who installed VS Code Server"
        exit 1
    fi
    
    # Show what will be removed
    show_removal_plan
    
    # Confirm removal
    confirm_removal
    
    print_status "Starting uninstallation process..."
    
    # Stop any running processes first
    cleanup_processes
    
    # Remove systemd service
    remove_tunnel_service
    
    # Remove VS Code package
    remove_vscode
    
    # Remove Microsoft repository and GPG key
    remove_microsoft_repo
    
    # Remove user data and configuration
    remove_user_data
    
    # Clean up temporary files
    cleanup_temp_files
    
    print_success "VS Code Server uninstallation completed successfully!"
    echo
    echo "=============================================="
    echo "Uninstallation Summary:"
    echo "- VS Code CLI package removed"
    echo "- Systemd service removed"
    echo "- Microsoft repository removed"
    echo "- User data and configuration removed"
    echo "- Temporary files cleaned up"
    echo
    echo "Note: If you had other Microsoft packages installed,"
    echo "you may need to re-add the Microsoft repository for them."
    echo "=============================================="
}

# Run main function
main "$@"
