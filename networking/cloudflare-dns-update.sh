#!/bin/bash

# Check if script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install jq based on the distribution
install_jq() {
    if command_exists apt-get; then
        apt-get update && apt-get install -y jq
    elif command_exists yum; then
        yum install -y jq
    elif command_exists dnf; then
        dnf install -y jq
    elif command_exists zypper; then
        zypper install -y jq
    elif command_exists pacman; then
        pacman -Sy jq --noconfirm
    else
        echo "Could not install jq. Please install it manually."
        exit 1
    fi
}

# Check for jq and install if missing
if ! command_exists jq; then
    echo "jq is not installed. Attempting to install..."
    install_jq
    if ! command_exists jq; then
        echo "Failed to install jq. Please install it manually."
        exit 1
    fi
    echo "jq has been successfully installed."
fi

# Base configurations
LOG_FILE="/var/log/cloudflare_dns_update.log"

# Function to get the current timestamp in ISO 8601 format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Function to log messages
log_message() {
    local message="$1"
    echo "$(get_timestamp): ${message}" >> "${LOG_FILE}"
}

# Function to display usage
show_usage() {
    echo "Usage: $0 --token TOKEN --zone ZONE_ID --record RECORD [--include-root] [--force] [--output-all-records]"
    echo "Options:"
    echo "  --token TOKEN      Cloudflare API token"
    echo "  --zone ZONE_ID     Cloudflare Zone ID"
    echo "  --record RECORD    DNS record to update (e.g., *.example.com)"
    echo "  --include-root     Also update the root domain A record (e.g., example.com)"
    echo "  --force            Force update even if IP hasn't changed"
    echo "  --output-all-records  Display all DNS records for the zone"
    echo "  --help             Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --token YOUR_CF_TOKEN --zone YOUR_ZONE_ID --record *.example.com"
    echo "  $0 --token YOUR_CF_TOKEN --zone YOUR_ZONE_ID --record *.example.com --include-root"
    echo "  $0 --token YOUR_CF_TOKEN --zone YOUR_ZONE_ID --output-all-records"
}

# Function to get the current public IP address
get_current_ip() {
    curl -s https://api.ipify.org
}

# Function to URL encode a string
urlencode() {
    local string="$1"
    echo "$string" | sed 's/*/%2A/g; s/\./%2E/g'
}

# Function to extract root domain from wildcard record
get_root_domain() {
    local record_name="$1"
    # Remove the "*." prefix if it exists
    echo "$record_name" | sed 's/^\*\.//'
}

# Function to get the existing DNS record
get_existing_record() {
    local record_name="$1"
    local zone_id="$2"
    local auth_token="$3"
    
    # URL encode the record name
    local encoded_name=$(urlencode "$record_name")
    
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&name=$record_name" \
         --header "Authorization: Bearer $auth_token" \
         -H "Content-Type: application/json"
}

# Function to get all DNS records for a zone
get_all_records() {
    local zone_id="$1"
    local auth_token="$2"
    
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?per_page=100" \
         --header "Authorization: Bearer $auth_token" \
         -H "Content-Type: application/json"
}

# Function to display all DNS records
display_all_records() {
    local zone_id="$1"
    local auth_token="$2"
    
    echo "Fetching all DNS records for zone $zone_id..."
    local response=$(get_all_records "$zone_id" "$auth_token")
    
    if ! echo "$response" | jq -e '.success' >/dev/null; then
        echo "Error: Failed to fetch DNS records"
        log_message "ERROR: Failed to fetch DNS records for zone $zone_id"
        return 1
    fi
    
    local record_count=$(echo "$response" | jq '.result | length')
    echo "Found $record_count DNS records:"
    echo
    
    # Format and display records
    echo "$response" | jq -r '.result[] | "Type: \(.type)\tName: \(.name)\tContent: \(.content)\tTTL: \(.ttl)\tProxied: \(.proxied)"' | \
    column -t -s '\t'
    
    log_message "Successfully displayed all DNS records for zone $zone_id"
    return 0
}

# Function to create a new DNS record
create_dns_record() {
    local record_name="$1"
    local zone_id="$2"
    local auth_token="$3"
    local current_ip="$4"
    
    local result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
         --header "Authorization: Bearer $auth_token" \
         -H "Content-Type: application/json" \
         --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$current_ip\",\"ttl\":1,\"proxied\":false}")
    
    if echo "$result" | jq -e '.success' >/dev/null; then
        echo "success"
    else
        echo "failed"
    fi
}

# Function to update the DNS record
update_dns() {
    local record_name="$1"
    local record_id="$2"
    local zone_id="$3"
    local auth_token="$4"
    local current_ip="$5"
    
    local result=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
         --header "Authorization: Bearer $auth_token" \
         -H "Content-Type: application/json" \
         --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$current_ip\",\"ttl\":1,\"proxied\":false}")
    
    if echo "$result" | jq -e '.success' >/dev/null; then
        echo "success"
    else
        echo "failed"
    fi
}

# Function to process a single DNS record (update or create)
process_dns_record() {
    local record_name="$1"
    local zone_id="$2"
    local auth_token="$3"
    local current_ip="$4"
    local force_update="$5"
    
    echo "Processing DNS record: $record_name"
    
    # Get existing record
    local response=$(get_existing_record "$record_name" "$zone_id" "$auth_token")
    
    # Check if the record exists
    if echo "$response" | jq -e '.result[0]' >/dev/null; then
        # Record exists - check if update is needed
        local existing_ip=$(echo "$response" | jq -r '.result[0].content')
        local record_id=$(echo "$response" | jq -r '.result[0].id')
        
        echo "  Found existing record with IP: $existing_ip"
        
        # Update DNS if needed
        if [ "$force_update" = "true" ] || [ "$current_ip" != "$existing_ip" ]; then
            echo "  Updating record from $existing_ip to $current_ip"
            local update_result=$(update_dns "$record_name" "$record_id" "$zone_id" "$auth_token" "$current_ip")
            
            if [ "$update_result" = "success" ]; then
                echo "  ✓ Successfully updated DNS record for $record_name"
                log_message "Updated DNS record for $record_name from $existing_ip to $current_ip"
                return 0
            else
                echo "  ✗ Failed to update DNS record for $record_name"
                log_message "Failed to update DNS record for $record_name"
                return 1
            fi
        else
            echo "  No update needed. Current IP ($current_ip) matches existing DNS record."
            log_message "No update needed for $record_name. Current IP ($current_ip) matches existing DNS record."
            return 0
        fi
    else
        # Record doesn't exist - create it
        echo "  Record not found, creating new record with IP: $current_ip"
        local create_result=$(create_dns_record "$record_name" "$zone_id" "$auth_token" "$current_ip")
        
        if [ "$create_result" = "success" ]; then
            echo "  ✓ Successfully created DNS record for $record_name"
            log_message "Created new DNS record for $record_name with IP $current_ip"
            return 0
        else
            echo "  ✗ Failed to create DNS record for $record_name"
            log_message "Failed to create DNS record for $record_name"
            return 1
        fi
    fi
}

# Parse command line arguments
AUTH_TOKEN=""
ZONE_ID=""
RECORD_NAME=""
INCLUDE_ROOT="false"
FORCE_UPDATE="false"
OUTPUT_ALL_RECORDS="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            AUTH_TOKEN="$2"
            shift 2
            ;;
        --zone)
            ZONE_ID="$2"
            shift 2
            ;;
        --record)
            RECORD_NAME="$2"
            shift 2
            ;;
        --include-root)
            INCLUDE_ROOT="true"
            shift
            ;;
        --force)
            FORCE_UPDATE="true"
            shift
            ;;
        --output-all-records)
            OUTPUT_ALL_RECORDS="true"
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
if [ -z "$AUTH_TOKEN" ] || [ -z "$ZONE_ID" ]; then
    log_message "ERROR: --token and --zone are required"
    show_usage
    exit 1
fi

# Handle the --output-all-records option
if [ "$OUTPUT_ALL_RECORDS" = "true" ]; then
    display_all_records "$ZONE_ID" "$AUTH_TOKEN"
    exit $?
fi

# Validate record name is provided for update operation
if [ -z "$RECORD_NAME" ]; then
    log_message "ERROR: --record is required when not using --output-all-records"
    show_usage
    exit 1
fi

# Get current public IP
CURRENT_IP=$(get_current_ip)
if [ -z "$CURRENT_IP" ]; then
    log_message "ERROR: Failed to get current public IP address"
    exit 1
fi

echo "Current public IP: $CURRENT_IP"
echo

# Track overall success
OVERALL_SUCCESS=0

# Process the main record (wildcard or specific)
if ! process_dns_record "$RECORD_NAME" "$ZONE_ID" "$AUTH_TOKEN" "$CURRENT_IP" "$FORCE_UPDATE"; then
    OVERALL_SUCCESS=1
fi

# Process root domain record if requested
if [ "$INCLUDE_ROOT" = "true" ]; then
    ROOT_DOMAIN=$(get_root_domain "$RECORD_NAME")
    
    # Only process root domain if it's different from the main record
    if [ "$ROOT_DOMAIN" != "$RECORD_NAME" ]; then
        echo
        if ! process_dns_record "$ROOT_DOMAIN" "$ZONE_ID" "$AUTH_TOKEN" "$CURRENT_IP" "$FORCE_UPDATE"; then
            OVERALL_SUCCESS=1
        fi
    else
        echo
        echo "Note: Root domain is the same as the specified record, skipping duplicate processing."
    fi
fi

echo
if [ $OVERALL_SUCCESS -eq 0 ]; then
    echo "✓ All DNS operations completed successfully!"
    log_message "All DNS operations completed successfully for records related to $RECORD_NAME"
else
    echo "✗ Some DNS operations failed. Check the log for details."
    log_message "Some DNS operations failed for records related to $RECORD_NAME"
fi

exit $OVERALL_SUCCESS