# Cloudflare DNS Update Script

A robust bash script for automatically updating Cloudflare DNS A records with your current public IP address. Supports wildcard domains, root domain updates, and batch operations.

## Features

- **Automatic IP Detection**: Retrieves your current public IP address
- **Wildcard Domain Support**: Update wildcard DNS records (e.g., `*.example.com`)
- **Root Domain Updates**: Optionally update root domain alongside wildcard records
- **Smart Updates**: Only updates when IP changes (unless forced)
- **Auto-Create Records**: Creates DNS records if they don't exist
- **Batch Operations**: View all DNS records in a zone
- **Cross-Platform**: Works on major Linux distributions
- **Automatic Dependencies**: Installs `jq` if not present
- **Comprehensive Logging**: Logs all operations to `/var/log/cloudflare_dns_update.log`

## Prerequisites

- Root or sudo access (for installing dependencies and writing logs)
- Cloudflare API token with DNS edit permissions
- Cloudflare Zone ID for your domain
- `curl` (usually pre-installed)
- `jq` (auto-installed if missing)

## Installation

1. Ensure the script is executable:
```bash
chmod +x cloudflare-dns-update.sh
```

2. The script will automatically install `jq` if it's not present on your system.

## Usage

### Basic usage for updating a wildcard domain:
```bash
sudo ./cloudflare-dns-update.sh --token YOUR_CF_TOKEN --zone YOUR_ZONE_ID --record "*.example.com"
```

### Update wildcard and root domain:
```bash
sudo ./cloudflare-dns-update.sh --token YOUR_CF_TOKEN --zone YOUR_ZONE_ID --record "*.example.com" --include-root
```

### Force update even if IP hasn't changed:
```bash
sudo ./cloudflare-dns-update.sh --token YOUR_CF_TOKEN --zone YOUR_ZONE_ID --record "*.example.com" --force
```

### View all DNS records in a zone:
```bash
sudo ./cloudflare-dns-update.sh --token YOUR_CF_TOKEN --zone YOUR_ZONE_ID --output-all-records
```

## Command Line Options

| Option | Description | Required |
|--------|-------------|----------|
| `--token TOKEN` | Cloudflare API token | Yes |
| `--zone ZONE_ID` | Cloudflare Zone ID | Yes |
| `--record RECORD` | DNS record to update (e.g., *.example.com) | Yes* |
| `--include-root` | Also update the root domain A record | No |
| `--force` | Force update even if IP hasn't changed | No |
| `--output-all-records` | Display all DNS records for the zone | No |
| `--help` | Show help message | No |

*Not required when using `--output-all-records`

## Getting Cloudflare Credentials

### API Token
1. Log in to your Cloudflare dashboard
2. Go to "My Profile" → "API Tokens"
3. Click "Create Token"
4. Use the "Edit zone DNS" template or create a custom token with:
   - Permissions: Zone → DNS → Edit
   - Zone Resources: Include → Specific zone → Your domain

### Zone ID
1. Log in to your Cloudflare dashboard
2. Select your domain
3. Find the Zone ID in the right sidebar of the Overview page

## Examples

### Update subdomain record only:
```bash
sudo ./cloudflare-dns-update.sh --token "your-api-token" --zone "your-zone-id" --record "home.example.com"
```

### Update wildcard and root domain:
```bash
sudo ./cloudflare-dns-update.sh --token "your-api-token" --zone "your-zone-id" --record "*.example.com" --include-root
```

### Check current DNS records before updating:
```bash
# First, view all records
sudo ./cloudflare-dns-update.sh --token "your-api-token" --zone "your-zone-id" --output-all-records

# Then update specific record
sudo ./cloudflare-dns-update.sh --token "your-api-token" --zone "your-zone-id" --record "*.example.com"
```

## Automation with Cron

To automatically update your DNS records when your IP changes, add a cron job:

1. Open crontab as root:
```bash
sudo crontab -e
```

2. Add one of these entries:

Update every 15 minutes:
```cron
*/15 * * * * /path/to/cloudflare-dns-update.sh --token "YOUR_TOKEN" --zone "YOUR_ZONE_ID" --record "*.example.com" --include-root
```

Update every hour:
```cron
0 * * * * /path/to/cloudflare-dns-update.sh --token "YOUR_TOKEN" --zone "YOUR_ZONE_ID" --record "*.example.com" --include-root
```

## Logging

All operations are logged to `/var/log/cloudflare_dns_update.log` with timestamps in ISO 8601 format.

View recent log entries:
```bash
sudo tail -f /var/log/cloudflare_dns_update.log
```

## Security Considerations

1. **API Token Security**: Store your API token securely. Consider using environment variables or a secure configuration file with restricted permissions.

2. **Minimal Permissions**: Create API tokens with only the necessary permissions (DNS Edit for specific zones).

3. **Log File Permissions**: The log file is created with root ownership. Ensure it's not world-readable if you're concerned about IP address privacy.

## Troubleshooting

### Permission Denied
- Ensure you're running the script with `sudo` or as root
- Check file permissions: `ls -la cloudflare-dns-update.sh`

### API Errors
- Verify your API token has DNS edit permissions
- Check that the Zone ID is correct
- Ensure the API token is valid and not expired

### IP Detection Failed
- Check your internet connection
- Verify that `https://api.ipify.org` is accessible
- Try running: `curl -s https://api.ipify.org`

### Record Not Updating
- Use `--force` flag to force an update
- Check logs for specific error messages
- Verify the record name matches exactly (including subdomains)

## Exit Codes

- `0`: Success - All operations completed successfully
- `1`: Error - One or more operations failed

## License

This script is provided as-is for use in managing Cloudflare DNS records.