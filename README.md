# Bash Scripts Collection

A comprehensive collection of useful bash scripts organized by category for system administration, automation, and development tasks.

## 📁 Repository Structure

```
bash-scripts/
├── networking/          # Network-related scripts
├── sysadmin/            # System administration utilities
├── automation/          # Automation and workflow scripts
├── utilities/           # General purpose utilities
├── security/            # Security and hardening scripts
├── backup/              # Backup and restore scripts
└── monitoring/          # Monitoring and alerting scripts
```

## 🚀 Featured Scripts

### 🌐 Networking

- **[cloudflare-dns-update.sh](networking/cloudflare-dns-update.sh)** - Dynamic DNS updater for Cloudflare
  - Updates A records with current public IP
  - Supports wildcard and root domain updates
  - Auto-installs dependencies (jq)
  - Comprehensive logging and error handling

- **[cert-renewal.sh](networking/cert-renewal.sh)** - Automated SSL/TLS certificate management
  - Generates both ECC and RSA certificates via Let's Encrypt
  - Uses Cloudflare DNS validation
  - Docker-based for portability
  - Automatic nginx integration

## 📖 Usage Guidelines

### Prerequisites

Most scripts require:
- Bash 4.0 or higher
- Basic utilities: `curl`, `jq` (auto-installed where possible)
- Appropriate permissions (some scripts require root access)

### Running Scripts

1. Make scripts executable:
   ```bash
   chmod +x script-name.sh
   ```

2. Run with appropriate permissions:
   ```bash
   # For regular scripts
   ./script-name.sh

   # For scripts requiring root access
   sudo ./script-name.sh
   ```

### Script Features

All scripts in this collection include:
- ✅ Comprehensive error handling
- ✅ Usage documentation and help text
- ✅ Input validation and sanity checks
- ✅ Logging capabilities where appropriate
- ✅ Cross-distribution compatibility where possible

## 🔧 Installation

### Quick Start

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/bash-scripts.git
cd bash-scripts

# Make all scripts executable
find . -name "*.sh" -type f -exec chmod +x {} \;
```

### Individual Script Installation

```bash
# Download a specific script
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/bash-scripts/main/networking/cloudflare-dns-update.sh
chmod +x cloudflare-dns-update.sh
```

## 📚 Script Documentation

Each script includes:
- Header with description and usage
- Built-in help (`--help` flag)
- Example usage commands
- Required dependencies
- Configuration options

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Script Standards:**
   - Include proper shebang (`#!/bin/bash`)
   - Add comprehensive error handling
   - Include usage function with `--help`
   - Use consistent coding style
   - Test on multiple distributions when possible

2. **Documentation:**
   - Update README.md with new script descriptions
   - Include usage examples
   - Document any dependencies

3. **Organization:**
   - Place scripts in appropriate category folders
   - Use descriptive, kebab-case filenames
   - Include `.sh` extension

## 📋 Categories Explained

| Category | Purpose | Examples |
|----------|---------|----------|
| `networking/` | Network configuration, DNS, connectivity | DNS updaters, network scanners, connectivity tests |
| `sysadmin/` | System maintenance and administration | User management, service control, system cleanup |
| `automation/` | Workflow automation and scheduling | Deployment scripts, batch operations, cron helpers |
| `utilities/` | General purpose tools and helpers | File operations, text processing, calculations |
| `security/` | Security hardening and analysis | Permission audits, security scans, hardening |
| `backup/` | Data backup and restoration | File backups, database dumps, sync scripts |
| `monitoring/` | System monitoring and alerting | Health checks, log analysis, alerting |

## 🛡️ Security Notes

- Always review scripts before execution
- Run with minimal required privileges
- Be cautious with scripts requiring root access
- Validate all inputs and environment variables
- Keep sensitive data (API keys, passwords) in separate config files

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

- Create an issue for bug reports or feature requests
- Check existing issues before creating new ones
- Provide detailed information including:
  - Operating system and version
  - Bash version (`bash --version`)
  - Complete error messages
  - Steps to reproduce

---

**Happy scripting!** 🎉