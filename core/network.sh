#!/bin/bash

# core/network.sh - Network management for dblab
# Handles isolated and engine-shared network creation and management

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/runner.sh"

# Network configuration
readonly NETWORK_PREFIX="dblab"

# Get network name for instance
get_instance_network_name() {
    local engine="$1"
    local instance="$2"
    local mode="${3:-isolated}"
    
    case "$mode" in
        isolated)
            echo "${NETWORK_PREFIX}_${engine}_${instance}_net"
            ;;
        engine-shared)
            echo "${NETWORK_PREFIX}_${engine}_shared_net"
            ;;
        *)
            die "Unknown network mode: $mode"
            ;;
    esac
}

# Create network with error handling
create_network() {
    local network_name="$1"
    local driver="${2:-bridge}"
    
    log_debug "Creating network: $network_name"
    log_trace "DBLAB_CONTAINER_RUNTIME in create_network: ${DBLAB_CONTAINER_RUNTIME:-UNSET}"
    
    # Initialize runner if not already done
    if [[ -z "${DBLAB_CONTAINER_RUNTIME:-}" ]]; then
        init_runner
    fi
    
    if network_exists "$network_name"; then
        log_debug "Network already exists: $network_name"
        return 0
    fi
    
    local runtime="${DBLAB_CONTAINER_RUNTIME}"
    
    # Create network with appropriate configuration
    local create_cmd=("$runtime" "network" "create")
    
    # Add driver
    create_cmd+=("--driver" "$driver")
    
    # For rootless podman, we might need additional configuration
    if [[ "$runtime" == "podman" && "$(get_runtime_capability rootless)" == "true" ]]; then
        # Rootless podman networks work fine with default settings
        log_trace "Using rootless podman network configuration"
    fi
    
    # Add network name
    create_cmd+=("$network_name")
    
    log_debug "Executing: $(printf '%s ' "${create_cmd[@]}")"
    
    if "${create_cmd[@]}" >/dev/null; then
        log_debug "Network created successfully: $network_name"
    else
        die "Failed to create network: $network_name"
    fi
}

# Remove network with cleanup
remove_network() {
    local network_name="$1"
    local force="${2:-false}"
    
    # Initialize runner if not already done
    if [[ -z "${DBLAB_CONTAINER_RUNTIME:-}" ]]; then
        init_runner
    fi
    
    if ! network_exists "$network_name"; then
        return 0
    fi
    
    local runtime="${DBLAB_CONTAINER_RUNTIME}"
    
    # Check if any containers are using the network
    local connected_containers
    connected_containers=$("$runtime" network inspect "$network_name" --format "{{range .Containers}}{{.Name}} {{end}}" 2>/dev/null || echo "")
    
    if [[ -n "$connected_containers" && "$force" != "true" ]]; then
        log_warn "Network $network_name has connected containers: $connected_containers"
        log_warn "Use force=true to remove network anyway"
        return 1
    fi
    
    # Force disconnect containers if requested
    if [[ "$force" == "true" && -n "$connected_containers" ]]; then
        for container in $connected_containers; do
            "$runtime" network disconnect "$network_name" "$container" 2>/dev/null || true
        done
    fi
    
    # Remove the network
    if "$runtime" network rm "$network_name" >/dev/null; then
        return 0
    else
        log_error "Failed to remove network: $network_name"
        return 1
    fi
}

# List dblab networks
list_dblab_networks() {
    local engine="${1:-}"
    
    # Initialize runner if not already done
    if [[ -z "${DBLAB_CONTAINER_RUNTIME:-}" ]]; then
        init_runner
    fi
    
    local runtime="${DBLAB_CONTAINER_RUNTIME}"
    local filter="${NETWORK_PREFIX}"
    
    if [[ -n "$engine" ]]; then
        filter="${NETWORK_PREFIX}_${engine}"
    fi
    
    log_info "dblab networks:"
    log_info "==============="
    
    # Get network information
    while IFS= read -r line; do
        if [[ "$line" =~ ^($filter[^[:space:]]*)[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$ ]]; then
            local net_name="${BASH_REMATCH[1]}"
            local driver="${BASH_REMATCH[2]}"
            local scope="${BASH_REMATCH[3]}"
            
            printf "  %-30s %-10s %s\n" "$net_name" "$driver" "$scope"
        fi
    done < <("$runtime" network ls --format "{{.Name}} {{.Driver}} {{.Scope}}" | grep "^${filter}" || true)
}

# Clean up orphaned networks
cleanup_orphaned_networks() {
    local force="${1:-false}"
    
    log_info "Cleaning up orphaned dblab networks..."
    
    # Initialize runner if not already done
    if [[ -z "${DBLAB_CONTAINER_RUNTIME:-}" ]]; then
        init_runner
    fi
    
    local runtime="${DBLAB_CONTAINER_RUNTIME}"
    local removed_count=0
    
    # Get all dblab networks
    while IFS= read -r network_name; do
        if [[ -n "$network_name" ]]; then
            # Check if network has any connected containers
            local connected_containers
            connected_containers=$("$runtime" network inspect "$network_name" --format "{{range .Containers}}{{.Name}} {{end}}" 2>/dev/null || echo "")
            
            if [[ -z "$connected_containers" ]]; then
                log_info "Removing orphaned network: $network_name"
                if remove_network "$network_name" "$force"; then
                    ((removed_count++))
                fi
            else
                log_debug "Network $network_name has connected containers: $connected_containers"
            fi
        fi
    done < <("$runtime" network ls --format "{{.Name}}" | grep "^${NETWORK_PREFIX}" || true)
    
    log_info "Removed $removed_count orphaned networks"
}

# Get network information
get_network_info() {
    local network_name="$1"
    local format="${2:-table}"
    
    # Initialize runner if not already done
    if [[ -z "${DBLAB_CONTAINER_RUNTIME:-}" ]]; then
        init_runner
    fi
    
    if ! network_exists "$network_name"; then
        die "Network does not exist: $network_name"
    fi
    
    local runtime="${DBLAB_CONTAINER_RUNTIME}"
    
    case "$format" in
        table)
            log_info "Network: $network_name"
            log_info "====================="
            "$runtime" network inspect "$network_name" --format "Driver: {{.Driver}}"
            "$runtime" network inspect "$network_name" --format "Scope: {{.Scope}}"
            "$runtime" network inspect "$network_name" --format "Created: {{.Created}}"
            
            log_info ""
            log_info "Connected containers:"
            "$runtime" network inspect "$network_name" --format "{{range .Containers}}  - {{.Name}} ({{.IPv4Address}}){{end}}" || echo "  (none)"
            ;;
        json)
            "$runtime" network inspect "$network_name"
            ;;
        *)
            die "Unknown format: $format"
            ;;
    esac
}

# Test network connectivity between containers
test_network_connectivity() {
    local network_name="$1"
    local container1="$2"
    local container2="$3"
    
    log_info "Testing connectivity between $container1 and $container2 on network $network_name"
    
    # Initialize runner if not already done
    if [[ -z "${DBLAB_CONTAINER_RUNTIME:-}" ]]; then
        init_runner
    fi
    
    if ! network_exists "$network_name"; then
        die "Network does not exist: $network_name"
    fi
    
    if ! container_running "$container1"; then
        die "Container $container1 is not running"
    fi
    
    if ! container_running "$container2"; then
        die "Container $container2 is not running"
    fi
    
    # Test ping connectivity
    if exec_container "$container1" ping -c 1 "$container2" >/dev/null 2>&1; then
        log_info "✅ Connectivity test passed: $container1 -> $container2"
        return 0
    else
        log_error "❌ Connectivity test failed: $container1 -> $container2"
        return 1
    fi
}

# Validate network configuration for engine/instance
validate_network_config() {
    local engine="$1"
    local instance="$2"
    local mode="$3"
    
    case "$mode" in
        isolated|engine-shared)
            # Valid modes
            ;;
        *)
            die "Invalid network mode: $mode. Must be 'isolated' or 'engine-shared'"
            ;;
    esac
}

# List containers in a network
list_network_containers() {
    local network_name="$1"
    
    if [[ -z "$network_name" ]]; then
        log_error "Network name is required"
        return 1
    fi
    
    if ! command_exists "${DBLAB_CONTAINER_RUNTIME}"; then
        log_error "Container runtime not available: ${DBLAB_CONTAINER_RUNTIME}"
        return 1
    fi
    
    # Check if network exists first
    if ! network_exists "$network_name"; then
        return 0  # Return empty list for non-existent network
    fi
    
    local containers
    case "${DBLAB_CONTAINER_RUNTIME}" in
        docker)
            # Use docker network inspect to get connected containers
            containers=$(docker network inspect "$network_name" --format '{{range $id, $container := .Containers}}{{$container.Name}} {{end}}' 2>/dev/null | tr ' ' '\n' | grep -v '^$' || true)
            ;;
        podman)
            # Use podman network inspect for connected containers
            containers=$(podman network inspect "$network_name" --format '{{range $id, $container := .Containers}}{{$container.Name}} {{end}}' 2>/dev/null | tr ' ' '\n' | grep -v '^$' || true)
            ;;
        *)
            log_error "Unsupported container runtime: ${DBLAB_CONTAINER_RUNTIME}"
            return 1
            ;;
    esac
    
    echo "$containers"
}

# Check if network exists
network_exists() {
    local network_name="$1"
    
    if [[ -z "$network_name" ]]; then
        return 1
    fi
    
    if ! command_exists "${DBLAB_CONTAINER_RUNTIME}"; then
        return 1
    fi
    
    case "${DBLAB_CONTAINER_RUNTIME}" in
        docker)
            docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"
            ;;
        podman)
            podman network ls --format '{{.Name}}' | grep -q "^${network_name}$"
            ;;
        *)
            return 1
            ;;
    esac
}

# Export functions for use by other modules
export -f get_instance_network_name create_network remove_network
export -f list_dblab_networks cleanup_orphaned_networks get_network_info
export -f test_network_connectivity validate_network_config list_network_containers network_exists
