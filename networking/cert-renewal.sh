#!/bin/bash

# Base configurations
CERT_DIR="/le-certs"
LOG_FILE="/var/log/cert-operations.log"

# Function to log messages with timestamps
log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${message}" | tee -a "${LOG_FILE}"
}

# Function to display usage
show_usage() {
    echo "Usage: $0 --domain DOMAIN --token TOKEN [--force]"
    echo "Options:"
    echo "  --domain DOMAIN     Domain to process (e.g., *.example.com)"
    echo "  --token TOKEN       Cloudflare API token"
    echo "  --force            Force certificate renewal"
    echo "  --help             Show this help message"
    echo
    echo "Example:"
    echo "  $0 --domain *.example.com --token YOUR_CF_TOKEN --force"
}

# Function to copy certificates to nginx
copy_to_nginx() {
    local domain="$1"
    local cert_type="$2"
    local nginx_dir="/etc/nginx/snippets"
    local source_dir=""
    local base_domain="${domain#\*.}"
    
    # Determine source directory based on cert type
    if [ "${cert_type}" = "ecc" ]; then
        source_dir="${CERT_DIR}/${domain}_ecc"
    else
        source_dir="${CERT_DIR}/${domain}"
    fi
    
    log_message "Copying ${cert_type} certificates to nginx for ${domain}"
    
    # Create nginx cert directory if it doesn't exist
    mkdir -p "${nginx_dir}/ssl"
    
    # Copy fullchain certificate
    cp "${source_dir}/fullchain.cer" "${nginx_dir}/ssl/${cert_type}_${base_domain}.crt"
    
    # Copy private key
    cp "${source_dir}/${domain}.key" "${nginx_dir}/ssl/${cert_type}_${base_domain}.key"
    
    # Set correct permissions
    chmod 644 "${nginx_dir}/ssl/${cert_type}_${base_domain}.crt"
    chmod 600 "${nginx_dir}/ssl/${cert_type}_${base_domain}.key"
    chown root:root "${nginx_dir}/ssl/${cert_type}_${base_domain}".{crt,key}
    
    log_message "Successfully copied ${cert_type} certificates to nginx"
}


process_cert() {
    local domain="$1"
    local cf_token="$2"
    local cert_type="$3"  # ecc or rsa
    local force_renewal="$4"
    
    log_message "Starting ${cert_type} certificate operation for ${domain}"
    
    # Force parameter if requested
    local force_param=""
    if [ "${force_renewal}" = "true" ]; then
        force_param="--force"
    fi
    
    # Set parameters based on certificate type
    local key_param=""
    local cert_domain="${domain}"
    if [ "${cert_type}" = "rsa" ]; then
        key_param="--keylength 2048"
    else
        # For ECC, let acme.sh handle the _ecc suffix
        key_param=""
    fi
    
    # Run acme.sh
    docker run --rm \
        -e CF_Token="${cf_token}" \
        -v "${CERT_DIR}":/acme.sh \
        neilpang/acme.sh --issue \
        -d "${cert_domain}" \
        --dns dns_cf \
        --server letsencrypt \
        --debug \
        ${key_param} \
        ${force_param} 2>&1 | tee -a "${LOG_FILE}"
        
    if [ $? -eq 0 ]; then
        log_message "Successfully processed ${cert_type} certificate for ${domain}"
    else
        log_message "ERROR: Failed to process ${cert_type} certificate for ${domain}"
        return 1
    fi
}

# Parse command line arguments
DOMAIN=""
CF_TOKEN=""
FORCE_RENEWAL="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --token)
            CF_TOKEN="$2"
            shift 2
            ;;
        --force)
            FORCE_RENEWAL="true"
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate command line arguments
if [ -z "$DOMAIN" ] || [ -z "$CF_TOKEN" ]; then
    log_message "ERROR: Both --domain and --token are required"
    show_usage
    exit 1
fi

# Create base directory if it doesn't exist
mkdir -p "${CERT_DIR}"

# Main execution starts here
log_message "Starting certificate operations for domain: ${DOMAIN}"

# Process ECC certificate
process_cert "${DOMAIN}" "${CF_TOKEN}" "ecc" "${FORCE_RENEWAL}"
copy_to_nginx "${DOMAIN}" "ecc"

# Process RSA certificate
process_cert "${DOMAIN}" "${CF_TOKEN}" "rsa" "${FORCE_RENEWAL}"
copy_to_nginx "${DOMAIN}" "rsa"

log_message "Certificate operations completed"