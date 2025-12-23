#!/bin/bash

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# Get instance file path
get_instance_file() {
    local engine="$1"
    local instance="$2"

    validate_engine_name "$engine"
    validate_instance_name "$instance"

    local data_dir
    data_dir=$(get_data_dir "$engine" "$instance")
    echo "${data_dir}/instance.yml"
}

# Check if instance exists
instance_exists() {
    local engine="$1"
    local instance="$2"

    local instance_file
    instance_file=$(get_instance_file "$engine" "$instance")

    [[ -f "$instance_file" ]]
}

# Generate container name for instance
get_container_name() {
    local engine="$1"
    local instance="$2"

    echo "dblab_${engine}_${instance}"
}

# Generate network name for instance
get_network_name() {
    local engine="$1"
    local instance="$2"
    local mode="${3:-isolated}"

    case "$mode" in
        isolated)
            echo "dblab_${engine}_${instance}_net"
            ;;
        engine-shared)
            echo "dblab_${engine}_shared_net"
            ;;
        *)
            die "Unknown network mode: $mode"
            ;;
    esac
}

# List all instances for an engine
list_instances() {
    local engine="$1"
    local verbose="${2:-false}"

    validate_engine_name "$engine"

    local engine_dir="${DBLAB_BASE_DIR}/${engine}"

    if [[ ! -d "$engine_dir" ]]; then
        log_info "No instances found for engine: $engine"
        return 0
    fi

    log_info "Instances for $engine:"
    log_info "====================="

    # Header
    if [[ "$verbose" == "true" ]]; then
        printf "  %-20s %-10s %-15s %-20s %-20s %-30s\n" \
               "NAME" "VERSION" "STATUS" "NETWORK_MODE" "CREATED" "DATA_DIR"
        printf "  %-20s %-10s %-15s %-20s %-20s %-30s\n" \
               "----" "-------" "------" "------------" "-------" "--------"
    else
        printf "  %-20s %-10s %-15s %-20s\n" \
               "NAME" "VERSION" "STATUS" "CREATED"
        printf "  %-20s %-10s %-15s %-20s\n" \
               "----" "-------" "------" "-------"
    fi

    local instance_count=0

    # Safely iterate through instances
    for instance_dir in "$engine_dir"/*; do
        # Skip if no files match the pattern
        [[ -e "$instance_dir" ]] || continue

        if [[ -d "$instance_dir" ]]; then
            local instance_name
            instance_name=$(basename "$instance_dir")
            local instance_file="${instance_dir}/instance.yml"

            if [[ -f "$instance_file" ]]; then
                # Extract basic info
                local version status created network_mode data_dir
                version=$(grep "^version:" "$instance_file" | cut -d: -f2 | tr -d ' "' || echo "unknown")
                status=$(grep "^[[:space:]]*status:" "$instance_file" | cut -d: -f2 | tr -d ' "' || echo "unknown")
                created=$(grep "^created:" "$instance_file" | cut -d: -f2 | tr -d ' "' || echo "unknown")
                network_mode=$(grep "^[[:space:]]*mode:" "$instance_file" | cut -d: -f2 | tr -d ' "' || echo "isolated")
                data_dir=$(grep "^[[:space:]]*data_dir:" "$instance_file" | cut -d: -f2- | tr -d ' "' || echo "unknown")

                # Truncate created timestamp for display
                created=$(echo "$created" | cut -c1-16)

                # Get real-time container status if available
                local real_status="$status"

                # Try to get real-time status if runner is available
                if declare -F get_container_name >/dev/null 2>&1 && declare -F get_container_status >/dev/null 2>&1; then
                    local container_name
                    if container_name=$(get_container_name "$engine" "$instance_name" 2>/dev/null); then
                        if [[ -n "$container_name" ]] && command_exists "${DBLAB_CONTAINER_RUNTIME:-docker}"; then
                            local runtime_status
                            if runtime_status=$(get_container_status "$container_name" 2>/dev/null); then
                                case "$runtime_status" in
                                    running)
                                        real_status="running"
                                        ;;
                                    exited|stopped)
                                        real_status="stopped"
                                        ;;
                                    not_found)
                                        real_status="not_found"
                                        ;;
                                    *)
                                        real_status="$status"
                                        ;;
                                esac
                            fi
                        fi
                    fi
                fi

                if [[ "$verbose" == "true" ]]; then
                    printf "  %-20s %-10s %-15s %-20s %-20s %-30s\n" \
                           "$instance_name" "$version" "$real_status" "$network_mode" "$created" "$data_dir"
                else
                    printf "  %-20s %-10s %-15s %-20s\n" \
                           "$instance_name" "$version" "$real_status" "$created"
                fi

                instance_count=$((instance_count + 1))
            fi
        fi
    done

    echo
    log_info "Total instances: $instance_count"

    return 0  # Explicit success return
}

# Remove instance completely
remove_instance() {
    local engine="$1"
    local instance="$2"
    local force="${3:-false}"

    if ! instance_exists "$engine" "$instance"; then
        log_warn "Instance does not exist: $engine/$instance"
        return 0
    fi

    local data_dir
    data_dir=$(get_data_dir "$engine" "$instance")

    if [[ "$force" != "true" ]]; then
        log_warn "This will permanently delete all data for $engine/$instance"
        log_warn "Data directory: $data_dir"
        read -p "Are you sure? (y/N): " -r confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            log_info "Instance removal cancelled"
            return 0
        fi
    fi

    log_info "Removing instance: $engine/$instance"

    # Handle permission issues that may occur with container-created files
    if [[ -d "$data_dir" ]] && ! touch "$data_dir/.dblab_test" 2>/dev/null; then
        log_debug "Permission issue detected, attempting to fix ownership"
        if command_exists sudo; then
            sudo chown -R "$(whoami)" "$data_dir" 2>/dev/null || true
        fi
    else
        # Clean up test file
        rm -f "$data_dir/.dblab_test" 2>/dev/null || true
    fi

    safe_rm "$data_dir"
    log_info "Instance removed successfully"
}

# Export functions for use by other modules
export -f instance_exists list_instances remove_instance get_container_name get_network_name get_instance_file
