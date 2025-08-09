#!/bin/bash

# Simple LXC migration script for Proxmox VE
# Uses numbered list for container selection

# Function to log messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to get all available nodes
get_nodes() {
    pvesh get /nodes --output-format json | jq -r '.[].node' 2>/dev/null || {
        # Fallback if jq is not available
        pvesh get /nodes | grep -E "^\s*[a-zA-Z0-9-]+" | awk '{print $1}' | grep -v "Node"
    }
}

# Function to get current node
get_current_node() {
    hostname
}

# Function to get all containers on current node
get_containers() {
    pct list | awk 'NR>1 && NF>=3 {
        vmid = $1
        status = $2
        name = ""
        # Name is everything from column 3 to the end
        for(i=3; i<=NF; i++) {
            name = (name ? name " " : "") $i
        }
        print vmid "|LXC|" name "|" status
    }'
}

# Function to display and select containers
select_containers() {
    local containers=("$@")
    
    # All of these echo/printf commands are for the user, so redirect to stderr
    echo "=== Proxmox LXC Migration Tool ===" >&2
    echo "Current Node: $CURRENT_NODE" >&2
    echo "Target Node: $TARGET_NODE" >&2
    echo "" >&2
    echo "Available LXC containers:" >&2
    echo "" >&2
    
    # Display all containers with numbers
    for i in "${!containers[@]}"; do
        local container_info="${containers[i]}"
        local vmid=$(echo "$container_info" | cut -d'|' -f1)
        local name=$(echo "$container_info" | cut -d'|' -f3)
        local status=$(echo "$container_info" | cut -d'|' -f4)
        
        printf "%2d. %-6s %-30s [%s]\n" "$((i+1))" "$vmid" "$name" "$status" >&2
    done
    
    echo "" >&2
    echo "Selection options:" >&2
    echo "  - Enter numbers separated by commas (e.g., 1,3,5)" >&2
    echo "  - Enter ranges with dash (e.g., 1-5,7,10-12)" >&2
    echo "  - Enter 'all' to select all containers" >&2
    echo "  - Enter 'q' to quit" >&2
    echo "" >&2
    
    while true; do
        # The prompt for read should also go to stderr, and input from the tty
        read -p "Your selection: " selection < /dev/tty
        
        case "$selection" in
            'q'|'Q')
                echo "Migration cancelled by user" >&2
                exit 0
                ;;
            'all'|'ALL')
                # This is the ACTUAL data output for mapfile, so it stays on stdout
                printf '%s\n' "${containers[@]}"
                return
                ;;
            *)
                # Parse the selection
                local selected_containers=()
                local valid_selection=true
                
                # Split by comma
                IFS=',' read -ra PARTS <<< "$selection"
                for part in "${PARTS[@]}"; do
                    # Remove whitespace
                    part=$(echo "$part" | xargs)
                    
                    if [[ "$part" =~ ^[0-9]+$ ]]; then
                        # Single number
                        local idx=$((part - 1))
                        if [[ $idx -ge 0 && $idx -lt ${#containers[@]} ]]; then
                            selected_containers+=("${containers[idx]}")
                        else
                            echo "Error: Invalid container number: $part" >&2
                            valid_selection=false
                            break
                        fi
                    elif [[ "$part" =~ ^[0-9]+-[0-9]+$ ]]; then
                        # Range like 1-5
                        local start=$(echo "$part" | cut -d'-' -f1)
                        local end=$(echo "$part" | cut -d'-' -f2)
                        
                        if [[ $start -le $end ]]; then
                            for ((j=start; j<=end; j++)); do
                                local idx=$((j - 1))
                                if [[ $idx -ge 0 && $idx -lt ${#containers[@]} ]]; then
                                    selected_containers+=("${containers[idx]}")
                                else
                                    echo "Error: Invalid container number in range: $j" >&2
                                    valid_selection=false
                                    break 2
                                fi
                            done
                        else
                            echo "Error: Invalid range: $part (start must be <= end)" >&2
                            valid_selection=false
                            break
                        fi
                    else
                        echo "Error: Invalid format: $part" >&2
                        valid_selection=false
                        break
                    fi
                done
                
                if [[ $valid_selection == true ]]; then
                    if [[ ${#selected_containers[@]} -gt 0 ]]; then
                        # Remove duplicates
                        local unique_containers=($(printf '%s\n' "${selected_containers[@]}" | sort -u))
                        # This is the ACTUAL data output for mapfile, so it stays on stdout
                        printf '%s\n' "${unique_containers[@]}"
                        return
                    else
                        echo "Error: No containers selected" >&2
                    fi
                fi
                
                echo "Please try again." >&2
                echo "" >&2
                ;;
        esac
    done
}


# Function to migrate a single container
migrate_container() {
    local container_info="$1"
    local vmid=$(echo "$container_info" | cut -d'|' -f1)
    local name=$(echo "$container_info" | cut -d'|' -f3)
    local status=$(echo "$container_info" | cut -d'|' -f4)
    
    log "Starting migration of LXC $vmid ($name) [$status] to $TARGET_NODE"
    
    if [[ "$status" == "running" ]]; then
        log "Container $vmid is running - performing migration with restart"
        if pct migrate $vmid "$TARGET_NODE" --restart; then
            log "SUCCESS: Container $vmid migrated successfully"
            return 0
        else
            log "ERROR: Failed to migrate container $vmid"
            return 1
        fi
    else
        log "Container $vmid is stopped - performing offline migration"
        if pct migrate $vmid "$TARGET_NODE"; then
            log "SUCCESS: Container $vmid migrated successfully"
            return 0
        else
            log "ERROR: Failed to migrate container $vmid"
            return 1
        fi
    fi
}

# Main function
main() {
    # Check if running as root or with appropriate permissions
    if [[ $EUID -ne 0 ]] && ! groups | grep -q "pveadmin\|root"; then
        echo "This script requires root privileges or pveadmin group membership"
        exit 1
    fi
    
    # Get current node
    CURRENT_NODE=$(get_current_node)
    log "Current node: $CURRENT_NODE"
    
    # Get available nodes
    log "Discovering available nodes..."
    mapfile -t available_nodes < <(get_nodes)
    
    if [[ ${#available_nodes[@]} -eq 0 ]]; then
        log "ERROR: No nodes found"
        exit 1
    fi
    
    # Remove current node from target options
    target_nodes=()
    for node in "${available_nodes[@]}"; do
        if [[ "$node" != "$CURRENT_NODE" ]]; then
            target_nodes+=("$node")
        fi
    done
    
    if [[ ${#target_nodes[@]} -eq 0 ]]; then
        log "ERROR: No target nodes available (only current node found)"
        exit 1
    fi
    
    # Select target node
    echo ""
    echo "Available target nodes:"
    for i in "${!target_nodes[@]}"; do
        echo "$((i+1)). ${target_nodes[i]}"
    done
    
    while true; do
        echo ""
        read -p "Select target node (1-${#target_nodes[@]}): " target_choice
        if [[ "$target_choice" =~ ^[0-9]+$ ]] && [[ $target_choice -ge 1 ]] && [[ $target_choice -le ${#target_nodes[@]} ]]; then
            TARGET_NODE="${target_nodes[$((target_choice-1))]}"
            break
        else
            echo "Invalid selection. Please enter a number between 1 and ${#target_nodes[@]}"
        fi
    done
    
    log "Target node selected: $TARGET_NODE"
    
    # Check target node accessibility
    if ! pvesh get /nodes/"$TARGET_NODE"/status >/dev/null 2>&1; then
        log "ERROR: Target node $TARGET_NODE is not accessible"
        exit 1
    fi
    
    log "Target node $TARGET_NODE is accessible"
    
    # Discover all containers on current node
    log "Discovering LXC containers on $CURRENT_NODE..."
    
    mapfile -t containers < <(get_containers)
    
    if [[ ${#containers[@]} -eq 0 ]]; then
        log "No LXC containers found on $CURRENT_NODE"
        exit 0
    fi
    
    log "Found ${#containers[@]} LXC containers on $CURRENT_NODE"
    echo ""
    
    # Select containers
    mapfile -t selected_containers < <(select_containers "${containers[@]}")
    
    if [[ ${#selected_containers[@]} -eq 0 ]]; then
        echo ""
        log "No containers selected for migration"
        exit 0
    fi
    
    # Confirm migration
    echo ""
    echo "=== Migration Summary ==="
    echo "Source Node: $CURRENT_NODE"
    echo "Target Node: $TARGET_NODE"
    echo "Selected LXC containers for migration:"
    echo ""
    
    for container in "${selected_containers[@]}"; do
        local vmid=$(echo "$container" | cut -d'|' -f1)
        local name=$(echo "$container" | cut -d'|' -f3)
        local status=$(echo "$container" | cut -d'|' -f4)
        echo "  - $vmid $name [$status]"
    done
    
    echo ""
    read -p "Proceed with migration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Migration cancelled"
        exit 0
    fi
    
    # Perform migrations
    log "Starting migration of ${#selected_containers[@]} containers"
    echo ""
    
    local success_count=0
    local failed_count=0
    local failed_containers=()
    
    for container in "${selected_containers[@]}"; do
        migrate_container "$container"
        local result=$? # Capture the exit code of the last command

        if [[ $result -eq 0 ]]; then
            ((success_count++))
        else
            ((failed_count++))
            local vmid=$(echo "$container" | cut -d'|' -f1)
            failed_containers+=("$vmid")
        fi
        echo "" # Add spacing between migrations
    done
    
    # Final summary
    log "Migration completed!"
    log "Successful migrations: $success_count"
    log "Failed migrations: $failed_count"
    
    if [[ $failed_count -gt 0 ]]; then
        log "Failed container IDs: ${failed_containers[*]}"
        exit 1
    fi
    
    log "All migrations completed successfully!"
}

# Run main function
main "$@"
