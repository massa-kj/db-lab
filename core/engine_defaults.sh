#!/bin/bash

# core/engine_defaults.sh - Default implementations for common engine operations
# These functions provide standard behavior that can be used by any container-based engine

set -euo pipefail

# Source required core utilities
DEFAULTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DEFAULTS_DIR}/lib.sh"
source "${DEFAULTS_DIR}/runner.sh"
source "${DEFAULTS_DIR}/instance_manager.sh"
source "${DEFAULTS_DIR}/instance_writer.sh"

default_engine_down() {
    local -n C="$1"

    local engine="${C[engine]}"
    local instance="${C[instance]}"

    log_info "Stopping instance: $instance"

    # Initialize runner
    init_runner

    local container_name
    container_name=$(get_container_name "$engine" "$instance")

    # Check if container is running
    if ! container_running "$container_name"; then
        log_info "Container is not running: $container_name"
        return 0
    fi

    # Stop container gracefully
    log_info "Stopping container: $container_name"
    stop_container "$container_name" 30  # 30 second timeout for PostgreSQL

    # Remove container
    remove_container "$container_name"

    # Update instance state if instance exists
    if instance_exists "$engine" "$instance"; then
        update_state_down "$engine" "$instance"
    fi

    log_info "PostgreSQL instance '$instance' stopped successfully"
}

# =============================================================
# Default destroy implementation for container-based engines
# =============================================================
# This function provides common destroy logic that works for most
# container-based database engines (PostgreSQL, MySQL, SQL Server, etc.)
#
# Engines can override this by defining their own engine_destroy function
# or provide engine-specific customization via CFG values
# =============================================================
default_engine_destroy() {
    local -n C="$1"

    local engine="${C[engine]}"
    local instance="${C[instance]}"

    log_info "Destroying $engine instance: $instance"

    # Initialize runner
    init_runner

    # Check if instance exists
    if ! instance_exists "$engine" "$instance"; then
        log_warn "Instance does not exist: $instance"
        return 0
    fi

    local container_name network_name data_dir
    container_name=$(get_container_name "$engine" "$instance")
    data_dir="${C[storage.data_dir]}"

    # Get network name from config
    local network_mode
    network_mode="${C[network.mode]:-isolated}"
    network_name=$(get_network_name "$engine" "$instance" "$network_mode")

    # Stop and remove container if running/exists
    if container_exists "$container_name"; then
        if container_running "$container_name"; then
            log_info "Stopping running container: $container_name"

            # Get engine-specific stop timeout (default 30 seconds)
            local stop_timeout
            stop_timeout="${C[engine.stop_timeout]:-60}"
            stop_container "$container_name" "$stop_timeout"
        fi

        log_info "Removing container: $container_name"
        remove_container "$container_name" true  # Force removal
    fi

    # Remove network if it's instance-specific and no other containers use it
    if [[ "$network_mode" == "isolated" ]]; then
        if network_exists "$network_name"; then
            local containers_in_network
            containers_in_network=$(list_network_containers "$network_name")

            if [[ -z "$containers_in_network" ]]; then
                log_info "Removing unused network: $network_name"
                remove_network "$network_name"
            else
                log_debug "Network still has containers, not removing: $network_name"
            fi
        fi
    fi

    # Handle data removal
    local data_removed="false"
    _handle_data_removal "$engine" "$instance" "$data_dir" C data_removed

    # Remove instance configuration
    log_info "Removing instance configuration"
    if [[ "$data_removed" == "true" ]]; then
        # Data was removed, safe to remove entire instance directory
        remove_instance "$engine" "$instance" true  # Force removal
    else
        # Data was preserved, only remove configuration files
        _remove_instance_config_only "$engine" "$instance"
    fi

    log_info "$engine instance '$instance' destroyed successfully"
}

# =============================================================
# Handle data directory removal with confirmation and permission handling
# =============================================================
_handle_data_removal() {
    local engine="$1"
    local instance="$2"
    local data_dir="$3"
    local -n cfg_ref="$4"
    local -n result_ref="$5"

    # Ask for confirmation before removing data
    local remove_data="false"
    local ephemeral
    ephemeral="${cfg_ref[storage.persistent]:-false}"

    if [[ "$ephemeral" == "true" ]]; then
        log_info "Instance is ephemeral, removing data automatically"
        remove_data="true"
    else
        log_warn "This will permanently delete all data for instance '$instance'"
        log_warn "Data directory: $data_dir"
        read -p "Are you sure you want to remove all data? (yes/no): " -r response

        case "$response" in
            yes|YES|y|Y)
                remove_data="true"
                ;;
            *)
                log_info "Data removal cancelled. Instance configuration removed but data preserved."
                remove_data="false"
                ;;
        esac
    fi

    # Remove data directory if confirmed
    if [[ "$remove_data" == "true" ]]; then
        if [[ -d "$data_dir" ]]; then
            log_info "Removing data directory: $data_dir"

            # Extract cleanup parameters from CFG
            local cleanup_image cleanup_command fallback_image
            cleanup_image="${cfg_ref[engine.cleanup.image]:-}"
            cleanup_command="${cfg_ref[engine.cleanup.command]:-}"
            fallback_image="${cfg_ref[image]:-}"

            # Try engine-specific cleanup first
            if _try_engine_specific_cleanup "$engine" "$data_dir" "$cleanup_image" "$cleanup_command" "$fallback_image"; then
                log_debug "Engine-specific cleanup succeeded"
            else
                # Fallback to generic cleanup
                _generic_cleanup "$data_dir"
            fi
        fi
        result_ref="true"
    else
        log_info "Data directory preserved: $data_dir"
        log_info "Note: Data was preserved and can be reused by creating a new instance"
        log_info "      with the same name and configuration."
        result_ref="false"
    fi
}

# =============================================================
# Try engine-specific cleanup using container runtime
# =============================================================
_try_engine_specific_cleanup() {
    local engine="$1"
    local data_dir="$2"
    local cleanup_image="$3"
    local cleanup_command="$4"
    local fallback_image="$5"

    # Check if container runtime is available
    if ! command_exists "${DBLAB_CONTAINER_RUNTIME}"; then
        return 1
    fi

    # Use provided cleanup image or fallback to main image
    if [[ -z "$cleanup_image" ]] && [[ -n "$fallback_image" ]]; then
        cleanup_image="$fallback_image"
    fi

    # Default cleanup command if not specified
    if [[ -z "$cleanup_command" ]]; then
        cleanup_command="rm -rf /data/*"
    fi

    # If still no cleanup image available, return failure
    if [[ -z "$cleanup_image" ]]; then
        return 1
    fi

    log_debug "Using container runtime to remove data with proper permissions"
    local temp_container="dblab-cleanup-$(date +%s)"

    # Run a temporary container to clean up with proper permissions
    if "${DBLAB_CONTAINER_RUNTIME}" run --rm \
        -v "${data_dir}:/data" \
        --name "$temp_container" \
        "$cleanup_image" \
        sh -c "$cleanup_command" 2>/dev/null; then

        # Remove the now-empty directory
        rmdir "$data_dir" 2>/dev/null || safe_rm "$data_dir"
        return 0
    else
        log_debug "Container-based cleanup failed, falling back to generic cleanup"
        return 1
    fi
}

# =============================================================
# Generic cleanup without container runtime
# =============================================================
_generic_cleanup() {
    local data_dir="$1"

    log_warn "Container runtime not available, trying to change permissions"

    # Try to change permissions first, then remove
    if command_exists sudo; then
        sudo chown -R "$(whoami)" "$data_dir" 2>/dev/null || true
    fi

    safe_rm "$data_dir"
}

# =============================================================
# Default status implementation
# =============================================================
default_engine_status() {
    local -n C="$1"

    local engine="${C[engine]}"
    local instance="${C[instance]}"

    init_runner

    local container_name
    container_name=$(get_container_name "$engine" "$instance")

    local status
    status=$(get_container_status "$container_name")

    echo "$status"
}

# Export functions for use by engines
export -f default_engine_down default_engine_destroy default_engine_status

# =============================================================
# Remove only instance configuration files, preserving data directory
# =============================================================
_remove_instance_config_only() {
    local engine="$1"
    local instance="$2"

    local instance_dir="${DBLAB_BASE_DIR}/${engine}/${instance}"
    local data_sub_dir="$instance_dir/data"

    if [[ ! -d "$instance_dir" ]]; then
        log_debug "Instance directory does not exist: $instance_dir"
        return 0
    fi

    log_debug "Removing configuration files from: $instance_dir"

    # Remove all files in instance directory except data subdirectory
    find "$instance_dir" -maxdepth 1 -type f -exec rm -f {} \; 2>/dev/null || true

    # Remove empty subdirectories but preserve data directory
    find "$instance_dir" -maxdepth 1 -type d -name "data" -prune -o -type d ! -path "$instance_dir" -exec rmdir {} \; 2>/dev/null || true

    log_debug "Configuration files removed, data directory preserved"
}

default_engine_list() {
    local engine="$1"
    local verbose_mode="${2:-false}"

    log_info "Listing $engine instances"

    # Source necessary modules for enhanced list functionality
    source "${SCRIPT_DIR}/instance_manager.sh"
    source "${SCRIPT_DIR}/runner.sh"

    # Initialize runner to get container status functions
    init_runner 2>/dev/null || true

    # Call the list instances function
    list_instances "$engine" "$verbose_mode"
}
