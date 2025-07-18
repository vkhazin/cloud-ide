# Cloud IDE Setup Script

This repository contains a script to set up a cloud-based development environment using code-server for web-based VS Code access.

---

## code-server.sh - Web-based VS Code IDE

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

## Security Considerations

- Uses HTTP Basic Authentication
- Implements SSL/TLS encryption
- Requires strong password (12+ chars, mixed case, numbers, symbols)
- Runs code-server without authentication (protected by NGINX)

## Troubleshooting

### Common Issues
- **Domain resolution errors**: Ensure DNS A record points to server IP
- **Certificate issues**: Check domain accessibility on port 80
- **Authentication failures**: Verify password meets complexity requirements
- **Service not starting**: Check logs with `sudo journalctl -u code-server -f`

### Getting Help
- Check service logs: `sudo journalctl -u code-server -f`
- Verify service status: `sudo systemctl status code-server`
- Test network connectivity: `curl -I https://your-domain.com/`
- Review NGINX config: `sudo nginx -t`

## License

These scripts are provided as-is for educational and development purposes. Please review and understand the code before running in production environments.
