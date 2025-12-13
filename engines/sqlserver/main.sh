#!/bin/bash

# engines/sqlserver/main.sh - SQL Server engine main operations
# Handles SQL Server container lifecycle (up/down/status)

set -euo pipefail

# Source core utilities
SQLSERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SQLSERVER_DIR}/../../core"
source "${CORE_DIR}/lib.sh"
source "${CORE_DIR}/runner.sh"
source "${CORE_DIR}/network.sh"
source "${CORE_DIR}/validator.sh"

# Engine-specific configuration
readonly ENGINE_NAME="sqlserver"

# Validate SQL Server-specific environment
validate_sqlserver_env() {
    log_debug "Validating SQL Server environment using metadata"
    
    # Additional SQL Server-specific password complexity validation
    local sa_password
    sa_password="$DBLAB_SQLSERVER_SA_PASSWORD"
    
    if [[ -n "$sa_password" ]]; then
        # Check for additional complexity requirements beyond minimum length
        local has_upper=false has_lower=false has_digit=false has_special=false
        
        if [[ "$sa_password" =~ [A-Z] ]]; then has_upper=true; fi
        if [[ "$sa_password" =~ [a-z] ]]; then has_lower=true; fi
        if [[ "$sa_password" =~ [0-9] ]]; then has_digit=true; fi
        if [[ "$sa_password" =~ [^a-zA-Z0-9] ]]; then has_special=true; fi
        
        local complexity_count=0
        [[ "$has_upper" == "true" ]] && ((complexity_count=complexity_count+1))
        [[ "$has_lower" == "true" ]] && ((complexity_count=complexity_count+1))
        [[ "$has_digit" == "true" ]] && ((complexity_count=complexity_count+1))
        [[ "$has_special" == "true" ]] && ((complexity_count=complexity_count+1))
        
        if [[ $complexity_count -lt 3 ]]; then
            die "SQL Server SA password must contain at least 3 of: uppercase, lowercase, digits, special characters"
        fi
    fi
    
    log_debug "SQL Server environment validation passed"
}

# Get the correct sqlcmd path based on SQL Server version
get_sqlcmd_path() {
    local version="$1"

    if [[ "$version" =~ ^2017 ]]; then
        echo "/opt/mssql-tools/bin/sqlcmd"
    else
        echo "/opt/mssql-tools18/bin/sqlcmd"
    fi
}

# Wait for SQL Server to be ready
wait_for_sqlserver() {
    local container_name="$1"
    local max_attempts="${2:-60}"  # SQL Server takes longer to start
    local sa_password="${3:-}"
    local version="${4:-}"
    local attempt=1
    
    log_info "Waiting for SQL Server to be ready (this may take a few minutes)..."
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Health check attempt $attempt/$max_attempts"
        
        # Use sqlcmd to check SQL Server readiness
        local sa_password version sqlcmd_path
        # sa_password=$(get_env "DBLAB_SQLSERVER_SA_PASSWORD")
        # version=$(get_env "DBLAB_SQLSERVER_VERSION")
        sqlcmd_path=$(get_sqlcmd_path "$version")

        if exec_container "$container_name" "$sqlcmd_path" \
            -C -S localhost -U sa -P "$sa_password" \
            -Q "SELECT 1" >/dev/null 2>&1; then
            log_info "SQL Server is ready!"
            return 0
        fi
        
        log_debug "SQL Server not ready yet, waiting..."
        sleep 5
        ((attempt++))
    done
    
    log_error "SQL Server failed to become ready within $((max_attempts * 5)) seconds"
    return 1
}

# Start SQL Server instance
engine_up() {
    local -n C="$1"
    
    local engine="${C[engine]}"
    local instance="${C[instance]}"
    
    log_info "Starting SQL Server instance: $instance"
    
    # Initialize runner first
    init_runner
    
    local container_name
    container_name=$(get_container_name "$engine" "$instance")
    
    # validate_sqlserver_env
    
    # Check if container is already running
    if container_running "$container_name"; then
        log_info "Container is already running: $container_name"
        return 0
    fi
    
    # Get instance configuration
    local data_dir network_name image
    data_dir="${C[storage.data_dir]:-${XDG_DATA_HOME:-$HOME/.local/share}/dblab/sqlserver/${instance}/data}"
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
    
    log_info "Starting SQL Server container: $container_name"
    
    # Build command arguments
    local run_args=(
        "--name" "${container_name}"
        "--network" "${network_name}"
        "-d"
        # SQL Server environment variables
        "-e" "ACCEPT_EULA=Y"
        "-e" "MSSQL_SA_PASSWORD=${C[db.password]}"
        "-e" "MSSQL_PID=${C[db.pid]:-Express}"
        "-e" "MSSQL_TCP_PORT=${C[db.port]}"
        # Data volume mount
        "-v" "${C[storage.data_dir]}:/var/opt/mssql"
    )

    # Add memory limit if specified
    local memory_limit="${C[runtime.resources.memory]:-}"
    if [[ -n "$memory_limit" ]]; then
        run_args+=("--memory=${memory_limit}")
    fi

    # Run as root to avoid permission issues  
    run_args+=("--user=0:0")

    # Expose port if specified
    local expose_enabled
    expose_enabled="${C[runtime.expose.enabled]:-false}"
    if [[ "$expose_enabled" == "true" ]]; then
        local expose_ports
        expose_ports="${C[runtime.expose.ports]:-}"

        if [[ -n "$expose_ports" ]]; then
            # If port is specified without host port (e.g., "1433"), 
            # map it to the same host port (e.g., "1433:1433")
            if [[ "$expose_ports" =~ ^[0-9]+$ ]]; then
                expose_ports="${expose_ports}:${expose_ports}"
                log_debug "Expanded port mapping to: $expose_ports"
            fi
            run_args+=("-p" "$expose_ports")
        fi
    fi

    runner_run "${image}" "${run_args[@]}"

    # Wait for SQL Server to be ready
    if ! wait_for_sqlserver "$container_name" 60 "${C[db.password]}" "${C[db.version]}"; then
        log_error "SQL Server startup failed"
        
        # Show logs for debugging
        log_error "Container logs:"
        get_container_logs "$container_name" 50
        
        # Stop and remove failed container
        stop_container "$container_name"
        remove_container "$container_name" true
        
        die "SQL Server startup failed"
    fi
    
    # Update instance state
    update_state_up "$engine" "$instance"
    
    log_info "SQL Server instance '$instance' started successfully"
    
    # Show connection information
    log_info "Connection details:"
    log_info "  Host: $container_name (in network: $network_name)"
    log_info "  Port: ${C[db.port]}"
    log_info "  Database: ${C[db.database]}"
    log_info "  User: sa"
    log_info "  Note: Use the SA password you configured"
}

# Connect to SQL Server CLI (sqlcmd)
engine_cli() {
    local -n C="$1"
    shift  # Remove first argument (config reference)

    # Get SQL Server container name to connect to
    # local sql_server_container
    # sql_server_container=$(get_container_name "$engine" "$instance")

    local BEFORE=()
    local AFTER=()
    
    # local host="${C[db.host]:-$sql_server_container}"
    local host="${C[db.host]:-}"
    local port="${C[db.port]:-1433}"
    local user="${C[db.user]}"
    local pass="${C[db.password]}"
    local db="${C[db.database]:-master}"

    local cli_container="${host}_cli"

    # CLI 用のイメージ（mcr.microsoft.com/mssql-toolsなど）
    local cli_image="${C[cli_image]}"

    local network_name
    network_name="${C[network.name]:-}"
    if [[ -z "$network_name" ]]; then
        # Fallback: generate network name from instance info
        local network_mode
        network_mode="${C[network.mode]:-isolated}"
        network_name=$(get_network_name "$engine" "$instance" "$network_mode")
    fi

    # Check if this is non-interactive mode (has -Q option)
    local use_interactive=true
    for arg in "$@"; do
        if [[ "$arg" == "-Q" ]]; then
            use_interactive=false
            break
        fi
    done
    
    BEFORE+=("--name=${cli_container}")
    BEFORE+=("--rm")
    BEFORE+=("--network=${network_name}")
    BEFORE+=("--env")
    BEFORE+=("SQLCMDPASSWORD=${pass}")
    if [[ "$use_interactive" == "true" ]]; then
        BEFORE+=("--interactive")
        BEFORE+=("--tty")
    fi
    
    AFTER+=("${C[cli_command]}")
    AFTER+=("-S" "${host},${port}")
    AFTER+=("-U" "${user}")
    # AFTER+=("-d" "${db}")
    # Pass through all additional arguments
    for arg in "$@"; do
        AFTER+=("$arg")
    done
    
    runner_run2 "${cli_image}" --before "${BEFORE[@]}" --after "${AFTER[@]}"
}

# Export functions for testing
export -f validate_sqlserver_env get_sqlcmd_path wait_for_sqlserver engine_up engine_cli
