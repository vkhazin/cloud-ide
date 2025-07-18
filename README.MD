# Cloud IDE Setup Scripts

This repository contains scripts to set up cloud-based development environments using VS Code. Choose the script that best fits your needs:

## Scripts Overview

### 1. `code-server.sh` - Web-based VS Code IDE
Sets up a web-accessible VS Code instance using code-server with NGINX reverse proxy and SSL/TLS encryption.

### 2. `vs-code-server.sh` - VS Code Tunnel Service
Sets up VS Code tunnel service for remote development using the official VS Code CLI.

---

## code-server.sh

### What it does
- Installs and configures [code-server](https://github.com/coder/code-server) for web-based VS Code access
- Sets up NGINX reverse proxy with SSL/TLS termination
- Configures Let's Encrypt certificates for HTTPS
- Implements HTTP Basic Authentication for security
- Creates systemd service for automatic startup

### Prerequisites
- Ubuntu Server 24.04
- VM with ports 22, 80, 443 accessible from the internet
- Domain name pointing to the server's public IP address
- Root or sudo access

### How to execute

#### Option 1: Direct execution (recommended)
```bash
bash <(curl -fsSL https://gist.githubusercontent.com/vkhazin/de15691155f54739c572d29bbb47b890/raw)
```

#### Option 2: Download and run locally
```bash
# Download the script
wget https://raw.githubusercontent.com/vkhazin/cloud-ide/main/code-server.sh

# Make it executable
chmod +x code-server.sh

# Run the script
./code-server.sh
```

### Interactive Setup Process
The script will prompt you for:

1. **Domain name** (e.g., `code.example.com`)
   - Must resolve to your server's public IP
   - Used for SSL certificate generation

2. **Username** for web access (default: `ubuntu`)

3. **Password** for web access
   - Minimum 12 characters
   - Must contain: lowercase, uppercase, number, special character

### What gets installed
- code-server (latest version)
- NGINX web server
- Certbot for Let's Encrypt certificates
- Apache2-utils for password hashing

### Access your IDE
After successful setup:
- URL: `https://your-domain.com/`
- Authentication: HTTP Basic Auth with your chosen credentials
- Features: Full VS Code experience in the browser

### Service Management
```bash
# Check code-server status
sudo systemctl status code-server

# Start/stop/restart code-server
sudo systemctl start code-server
sudo systemctl stop code-server
sudo systemctl restart code-server

# Check NGINX status
sudo systemctl status nginx

# View logs
sudo journalctl -u code-server -f
sudo journalctl -u nginx -f
```

---

## vs-code-server.sh

### What it does
- Installs VS Code CLI with tunnel support
- Sets up VS Code tunnel service for remote connections
- Configures systemd service for automatic tunnel management
- Enables connection from any VS Code instance (desktop, web, mobile)

### Prerequisites
- Ubuntu 24.04 (optimized for this version)
- Internet connection
- GitHub or Microsoft account for authentication
- Root or sudo access

### How to execute

```bash
# Download the script
wget https://raw.githubusercontent.com/vkhazin/cloud-ide/main/vs-code-server.sh

# Make it executable
chmod +x vs-code-server.sh

# Run the script
./vs-code-server.sh
```

### Interactive Setup Process
The script will:

1. **Update system packages**
2. **Install VS Code CLI** from Microsoft repository
3. **Prompt for tunnel name** (default: `hostname-tunnel`)
4. **Setup authentication** with GitHub/Microsoft account
5. **Create systemd service** for tunnel management
6. **Start the tunnel service**

### Authentication Process
- You'll receive a device code and URL
- Open the URL in your browser
- Enter the device code
- Sign in with GitHub or Microsoft account
- Grant necessary permissions

### Connecting to your tunnel

#### From VS Code Desktop
1. Install "Remote - Tunnels" extension
2. Open Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`)
3. Run "Remote-Tunnels: Connect to Tunnel"
4. Select your tunnel name
5. Choose to open in current window or new window

#### From VS Code Web (vscode.dev)
1. Go to [vscode.dev](https://vscode.dev)
2. Click "Open Remote Repository"
3. Select "Connect to Tunnel"
4. Choose your tunnel name

#### From VS Code Mobile
1. Install VS Code mobile app
2. Sign in with the same account
3. Connect to your tunnel

### Service Management
```bash
# Check tunnel service status
sudo systemctl status vscode-tunnel

# Start/stop/restart tunnel
sudo systemctl start vscode-tunnel
sudo systemctl stop vscode-tunnel
sudo systemctl restart vscode-tunnel

# View tunnel logs
sudo journalctl -u vscode-tunnel -f

# Manual tunnel command
code tunnel --name your-tunnel-name
```

---

## Comparison: code-server vs VS Code Tunnel

| Feature | code-server.sh | vs-code-server.sh |
|---------|----------------|-------------------|
| **Access Method** | Web browser only | Any VS Code client |
| **Authentication** | HTTP Basic Auth | GitHub/Microsoft OAuth |
| **SSL/HTTPS** | ✅ (Let's Encrypt) | ✅ (Built-in) |
| **Domain Required** | ✅ Yes | ❌ No |
| **Firewall Setup** | Ports 80, 443 | No special ports |
| **Extensions** | Web-compatible only | Full extension support |
| **Performance** | Good for web | Native performance |
| **Offline Access** | ❌ No | ✅ Yes (when synced) |
| **Mobile Support** | ✅ Any browser | ✅ VS Code mobile app |

## Choose Your Setup

### Use `code-server.sh` if you:
- Want browser-based access only
- Need a simple, self-contained solution
- Have a domain name available
- Prefer traditional web authentication
- Want to share access with multiple users

### Use `vs-code-server.sh` if you:
- Want to use desktop VS Code remotely
- Need full extension compatibility
- Don't have a domain name
- Prefer OAuth authentication
- Want the native VS Code experience

## Troubleshooting

### Common Issues

#### code-server.sh
- **Domain resolution errors**: Ensure DNS A record points to server IP
- **Certificate issues**: Check domain accessibility on port 80
- **Authentication failures**: Verify password meets complexity requirements
- **Service not starting**: Check logs with `sudo journalctl -u code-server -f`

#### vs-code-server.sh
- **Authentication timeout**: Complete browser authentication within 5 minutes
- **Tunnel not visible**: Ensure you're signed in with the same account
- **Connection refused**: Check service status and restart if needed
- **Permission errors**: Don't run the script as root

### Getting Help
- Check service logs: `sudo journalctl -u [service-name] -f`
- Verify service status: `sudo systemctl status [service-name]`
- Test network connectivity: `curl -I https://your-domain.com/`
- Review NGINX config: `sudo nginx -t`

## Security Considerations

### code-server.sh
- Uses HTTP Basic Authentication
- Implements SSL/TLS encryption
- Requires strong password (12+ chars, mixed case, numbers, symbols)
- Runs code-server without authentication (protected by NGINX)

### vs-code-server.sh
- Uses OAuth with GitHub/Microsoft
- Built-in encryption for tunnel connections
- No exposed ports (outbound connections only)
- Automatic token refresh

## License

These scripts are provided as-is for educational and development purposes. Please review and understand the code before running in production environments.
