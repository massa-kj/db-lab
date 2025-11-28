#!/bin/bash

# engines/postgres/main.sh - PostgreSQL engine main operations
# Handles PostgreSQL container lifecycle (up/down/status)

set -euo pipefail

# Source core utilities
POSTGRES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${POSTGRES_DIR}/../../core"
source "${CORE_DIR}/lib.sh"
source "${CORE_DIR}/env_loader.sh"
source "${CORE_DIR}/instance_loader.sh"
source "${CORE_DIR}/runner.sh"
source "${CORE_DIR}/network.sh"
source "${CORE_DIR}/validator.sh"

# Engine-specific configuration
readonly ENGINE_NAME="postgres"
readonly METADATA_FILE="${POSTGRES_DIR}/metadata.yml"

# Validate PostgreSQL-specific environment
validate_postgres_env() {
    log_debug "Validating PostgreSQL environment using metadata"
    
    # Use the new metadata-driven validation
    if ! validate_env_against_metadata "$METADATA_FILE" "DBLAB_PG_"; then
        die "PostgreSQL environment validation failed"
    fi
    
    log_debug "PostgreSQL environment validation passed"
}

# Prepare PostgreSQL container configuration
prepare_postgres_container() {
    local instance="$1"
    local network_name="$2"
    local data_dir="$3"
    
    log_debug "Preparing PostgreSQL container configuration"
    
    # Get configuration
    version=$(get_env "DBLAB_PG_VERSION")
    user=$(get_env "DBLAB_PG_USER")
    password=$(get_env "DBLAB_PG_PASSWORD")
    database=$(get_env "DBLAB_PG_DATABASE")
    port=$(get_env "DBLAB_PG_PORT" "5432")

    local image="postgres:${version}"
    local container_name
    container_name=$(get_container_name "$ENGINE_NAME" "$instance")
    
    # Reset and configure runner
    reset_args
    set_container_name "$container_name"
    set_detached
    add_network "$network_name"
    
    # PostgreSQL environment variables
    add_env "POSTGRES_USER" "$user"
    add_env "POSTGRES_PASSWORD" "$password"
    add_env "POSTGRES_DB" "$database"
    
    # Data volume mount
    add_volume "${data_dir}:/var/lib/postgresql/data"
    
    # Expose port if specified
    local expose_enabled
    expose_enabled=$(get_env "DBLAB_EXPOSE_ENABLED" "false")
    
    if [[ "$expose_enabled" == "true" ]]; then
        local expose_ports
        expose_ports=$(get_env "DBLAB_EXPOSE_PORTS" "")
        
        if [[ -n "$expose_ports" ]]; then
            # If port is specified without host port (e.g., "5432"), 
            # map it to the same host port (e.g., "5432:5432")
            if [[ "$expose_ports" =~ ^[0-9]+$ ]]; then
                expose_ports="${expose_ports}:${expose_ports}"
                log_debug "Expanded port mapping to: $expose_ports"
            fi
            add_port "$expose_ports"
        fi
    fi
    
    # Set image last
    set_image "$image"
    
    log_debug "PostgreSQL container configuration prepared"
}

# Wait for PostgreSQL to be ready
wait_for_postgres() {
    local container_name="$1"
    local max_attempts="${2:-30}"
    local attempt=1
    
    log_info "Waiting for PostgreSQL to be ready..."
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Health check attempt $attempt/$max_attempts"
        
        # Use pg_isready to check PostgreSQL readiness
        if exec_container "$container_name" pg_isready -q >/dev/null 2>&1; then
            log_info "PostgreSQL is ready!"
            return 0
        fi
        
        log_debug "PostgreSQL not ready yet, waiting..."
        sleep 2
        ((attempt++))
    done
    
    log_error "PostgreSQL failed to become ready within $((max_attempts * 2)) seconds"
    return 1
}

# Start PostgreSQL instance
engine_up() {
    local -n C="$1"
    
    log_info "Starting PostgreSQL instance: $instance"
    
    # Initialize runner first
    init_runner
    
    local engine="${C[engine]}"
    local instance="${C[instance]}"
    local container_name
    container_name=$(get_container_name "$engine" "$instance")
    
    # Check if container is already running
    if container_running "$container_name"; then
        log_info "Container is already running: $container_name"
        return 0
    fi
    
    # Check if instance exists
    # local instance_exists=false
    # if instance_exists "$ENGINE_NAME" "$instance"; then
    #     log_debug "Loading existing instance: $instance"
    #     load_instance "$ENGINE_NAME" "$instance"
    #     instance_exists=true
    # else
    #     log_debug "Creating new instance: $instance"
        
    #     # Create new instance
    #     local version user password database network_mode ephemeral
    #     version=$(get_env "DBLAB_PG_VERSION")
    #     user=$(get_env "DBLAB_PG_USER")
    #     password=$(get_env "DBLAB_PG_PASSWORD")
    #     database=$(get_env "DBLAB_PG_DATABASE")
    #     network_mode=$(get_env "DBLAB_NETWORK_MODE" "isolated")
    #     ephemeral=$(get_env "DBLAB_EPHEMERAL" "false")
        
    #     create_instance "$ENGINE_NAME" "$instance" "$version" "$user" "$password" "$database" "$network_mode" "$ephemeral"
    #     load_instance "$ENGINE_NAME" "$instance"
    # fi
    
    # Get instance configuration
    local data_dir network_name version image
    data_dir="${C[storage.data_dir]:-${XDG_DATA_HOME:-$HOME/.local/share}/dblab/postgres/${instance}/data}"
    network_name="${C[network.name]:-}"
    if [[ -z "$network_name" ]]; then
        # Fallback: generate network name from instance info
        local network_mode
        network_mode="${C[network.mode]:-isolated}"
        network_name=$(get_network_name "$engine" "$instance" "$network_mode")
    fi
    image="${C[image]}"

    # Ensure directories exist
    ensure_dir "$data_dir"
    
    # Create network if it doesn't exist
    create_network "$network_name"
    
    # Ensure image is available
    ensure_image "$image"
    
    # Remove existing stopped container if exists
    if container_exists "$container_name" && ! container_running "$container_name"; then
        log_debug "Removing existing stopped container: $container_name"
        remove_container "$container_name"
    fi
    
    log_info "Starting PostgreSQL container: $container_name"
    
    # Build command arguments
    local run_args=(
        "--name" "${container_name}"
        "--network" "${network_name}"
        "-d"
        "-e" "POSTGRES_USER=${C[db.user]}"
        "-e" "POSTGRES_PASSWORD=${C[db.password]}"
        "-e" "POSTGRES_DB=${C[db.database]}"
        "-v" "${C[storage.data_dir]}:/var/lib/postgresql/data"
    )

    # Expose port if specified
    local expose_enabled
    expose_enabled="${C[runtime.expose.enabled]:-false}"
    if [[ "$expose_enabled" == "true" ]]; then
        local expose_ports
        expose_ports="${C[runtime.expose.ports]:-}"

        if [[ -n "$expose_ports" ]]; then
            # If port is specified without host port (e.g., "5432"), 
            # map it to the same host port (e.g., "5432:5432")
            if [[ "$expose_ports" =~ ^[0-9]+$ ]]; then
                expose_ports="${expose_ports}:${expose_ports}"
                log_debug "Expanded port mapping to: $expose_ports"
            fi
            run_args+=("-p" "$expose_ports")
        fi
    fi

    runner_run "${image}" "${run_args[@]}"
    
    # Wait for PostgreSQL to be ready
    if ! wait_for_postgres "$container_name"; then
        log_error "PostgreSQL startup failed"
        
        # Show logs for debugging
        log_error "Container logs:"
        get_container_logs "$container_name" 50
        
        # Stop and remove failed container
        stop_container "$container_name"
        remove_container "$container_name" true
        
        die "PostgreSQL startup failed"
    fi
    
    # Update instance state
    update_state_up "$engine" "$instance"
    
    log_info "PostgreSQL instance '$instance' started successfully"
    
    # Show connection information
    log_info "Connection details:"
    log_info "  Host: $container_name (in network: $network_name)"
    log_info "  Port: ${C[db.port]}"
    log_info "  Database: ${C[db.database]}"
    log_info "  User: ${C[db.user]}"
}

# Main command dispatcher
main() {
    local command="$1"
    local instance="$2"
    shift 2
    local args=("$@")
    
    case "$command" in
        up)
            postgres_up "$instance" "${args[@]}"
            ;;
        down)
            postgres_down "$instance"
            ;;
        status)
            postgres_status "$instance"
            ;;
        destroy)
            postgres_destroy "$instance"
            ;;
        *)
            die "Unknown PostgreSQL command: $command"
            ;;
    esac
}

# Export functions for testing
# export -f validate_postgres_env prepare_postgres_container wait_for_postgres
# export -f postgres_up postgres_down postgres_status postgres_destroy

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
