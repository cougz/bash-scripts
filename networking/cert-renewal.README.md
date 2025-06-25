# Certificate Creation and Renewal Script

Automated SSL/TLS certificate generation and renewal using acme.sh with Cloudflare DNS validation. Generates both ECC and RSA certificates and automatically configures them for nginx.

## Features

- **Dual Certificate Generation**: Creates both ECC (default) and RSA certificates
- **Cloudflare DNS Validation**: Uses Cloudflare API for DNS-01 challenge
- **Docker-based**: Runs acme.sh in a Docker container for portability
- **Nginx Integration**: Automatically copies certificates to nginx configuration
- **Wildcard Support**: Works with wildcard domains (*.example.com)
- **Force Renewal**: Option to force certificate renewal before expiry
- **Comprehensive Logging**: All operations logged to `/var/log/cert-operations.log`

## Prerequisites

- Docker installed and running
- Root or sudo access
- Cloudflare API token with DNS edit permissions
- nginx installed (for certificate deployment)

## Installation

1. Ensure the script is executable:
```bash
chmod +x cert-renewal.sh
```

2. Create the certificate directory (if not exists):
```bash
mkdir -p /le-certs
```

## Usage

### Basic certificate generation:
```bash
sudo ./cert-renewal.sh --domain "*.example.com" --token YOUR_CF_TOKEN
```

### Force renewal of existing certificates:
```bash
sudo ./cert-renewal.sh --domain "*.example.com" --token YOUR_CF_TOKEN --force
```

## Command Line Options

| Option | Description | Required |
|--------|-------------|----------|
| `--domain DOMAIN` | Domain to process (e.g., *.example.com) | Yes |
| `--token TOKEN` | Cloudflare API token | Yes |
| `--force` | Force certificate renewal | No |
| `--help` | Show help message | No |

## Certificate Types

The script generates two types of certificates for each domain:

1. **ECC Certificate** (Elliptic Curve)
   - Modern, smaller key size
   - Better performance
   - Stored in: `/le-certs/{domain}_ecc/`
   - nginx location: `/etc/nginx/snippets/ssl/ecc_{domain}.{crt,key}`

2. **RSA Certificate** (2048-bit)
   - Wider compatibility
   - Traditional certificate type
   - Stored in: `/le-certs/{domain}/`
   - nginx location: `/etc/nginx/snippets/ssl/rsa_{domain}.{crt,key}`

## Directory Structure

```
/le-certs/
├── *.example.com/          # RSA certificate files
│   ├── fullchain.cer
│   ├── *.example.com.key
│   └── ...
└── *.example.com_ecc/      # ECC certificate files
    ├── fullchain.cer
    ├── *.example.com.key
    └── ...

/etc/nginx/snippets/ssl/
├── ecc_example.com.crt     # ECC fullchain certificate
├── ecc_example.com.key     # ECC private key
├── rsa_example.com.crt     # RSA fullchain certificate
└── rsa_example.com.key     # RSA private key
```

## nginx Configuration Example

After running the script, you can configure nginx to use the certificates:

```nginx
server {
    listen 443 ssl http2;
    server_name example.com *.example.com;

    # ECC certificate (preferred)
    ssl_certificate /etc/nginx/snippets/ssl/ecc_example.com.crt;
    ssl_certificate_key /etc/nginx/snippets/ssl/ecc_example.com.key;

    # RSA certificate (fallback)
    ssl_certificate /etc/nginx/snippets/ssl/rsa_example.com.crt;
    ssl_certificate_key /etc/nginx/snippets/ssl/rsa_example.com.key;

    # ... rest of your configuration
}
```

## Automation with Cron

Let's Encrypt certificates expire after 90 days. Set up automatic renewal:

1. Open root's crontab:
```bash
sudo crontab -e
```

2. Add renewal job (runs daily at 2 AM):
```cron
0 2 * * * /path/to/cert-renewal.sh --domain "*.example.com" --token "YOUR_CF_TOKEN" && nginx -s reload
```

## Getting Cloudflare API Token

1. Log in to Cloudflare dashboard
2. Go to "My Profile" → "API Tokens"
3. Click "Create Token"
4. Use "Edit zone DNS" template or create custom token with:
   - Permissions: Zone → DNS → Edit
   - Zone Resources: Include → Specific zone → Your domain

## Logging

All operations are logged to `/var/log/cert-operations.log`:

```bash
# View recent logs
sudo tail -f /var/log/cert-operations.log

# Search for errors
sudo grep ERROR /var/log/cert-operations.log
```

## Troubleshooting

### Docker not found
```bash
# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl start docker
```

### Permission denied
- Ensure running with sudo or as root
- Check Docker daemon is accessible

### Certificate generation fails
- Verify Cloudflare API token has correct permissions
- Check domain is managed by Cloudflare
- Ensure DNS propagation time (wait 2-5 minutes after DNS changes)
- Check logs for specific error messages

### nginx reload fails after renewal
- Verify nginx configuration syntax: `nginx -t`
- Check certificate file permissions
- Ensure nginx ssl directory exists: `/etc/nginx/snippets/ssl/`

## Security Considerations

1. **API Token Security**: Store your Cloudflare API token securely
2. **Certificate Permissions**: Private keys are set to 600 (read-only by root)
3. **Log Files**: Contains domain information but no sensitive credentials
4. **Docker Security**: Uses official acme.sh image from Docker Hub

## Manual Certificate Operations

If you need to work with certificates manually:

```bash
# List certificates
docker run --rm -v /le-certs:/acme.sh neilpang/acme.sh --list

# Revoke certificate
docker run --rm -v /le-certs:/acme.sh neilpang/acme.sh --revoke -d "*.example.com"

# Remove certificate
docker run --rm -v /le-certs:/acme.sh neilpang/acme.sh --remove -d "*.example.com"
```

## License

This script is provided as-is for SSL/TLS certificate management with Let's Encrypt and Cloudflare.