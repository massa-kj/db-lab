#!/bin/bash

# engines/sqlserver/main.sh - SQL Server engine main operations
# Handles SQL Server container lifecycle (up/down/status)

set -euo pipefail

# Source core utilities
SQLSERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SQLSERVER_DIR}/../../core"
source "${CORE_DIR}/lib.sh"
source "${CORE_DIR}/env_loader.sh"
source "${CORE_DIR}/instance_loader.sh"
source "${CORE_DIR}/runner.sh"
source "${CORE_DIR}/network.sh"

# Engine-specific configuration
readonly ENGINE_NAME="sqlserver"
readonly METADATA_FILE="${SQLSERVER_DIR}/metadata.yml"

# Validate SQL Server-specific environment
validate_sqlserver_env() {
    log_debug "Validating SQL Server environment"
    
    local sa_password database
    sa_password=$(get_env "DBLAB_SQLSERVER_SA_PASSWORD")
    database=$(get_env "DBLAB_SQLSERVER_DATABASE")
    
    # Check required fields
    if [[ -z "$sa_password" ]]; then
        die "DBLAB_SQLSERVER_SA_PASSWORD is required"
    fi
    
    if [[ -z "$database" ]]; then
        die "DBLAB_SQLSERVER_DATABASE is required"
    fi
    
    # Validate SA password complexity (SQL Server requirement)
    if [[ ${#sa_password} -lt 8 ]]; then
        die "SQL Server SA password must be at least 8 characters long"
    fi
    
    # Check for complexity requirements
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
    
    # Validate database name format
    if [[ ! "$database" =~ ^[a-zA-Z0-9_]+$ ]]; then
        die "Invalid SQL Server database name: $database"
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

# Prepare SQL Server container configuration
prepare_sqlserver_container() {
    local instance="$1"
    local network_name="$2"
    local data_dir="$3"
    
    log_debug "Preparing SQL Server container configuration"
    
    # Get configuration
    version=$(get_env "DBLAB_SQLSERVER_VERSION")
    sa_password=$(get_env "DBLAB_SQLSERVER_SA_PASSWORD")
    database=$(get_env "DBLAB_SQLSERVER_DATABASE")
    port=$(get_env "DBLAB_SQLSERVER_PORT" "1433")
    
    local image="mcr.microsoft.com/mssql/server:${version}"
    local container_name
    container_name=$(get_container_name "$ENGINE_NAME" "$instance")
    
    # Reset and configure runner
    reset_args
    set_container_name "$container_name"
    set_detached
    add_network "$network_name"
    
    # SQL Server environment variables
    add_env "ACCEPT_EULA" "Y"
    add_env "MSSQL_SA_PASSWORD" "$sa_password"
    add_env "MSSQL_PID" "Express"  # Use Express edition for development
    add_env "MSSQL_TCP_PORT" "$port"
    
    # Data volume mount with proper permissions
    add_volume "${data_dir}:/var/opt/mssql"
    
    # Set memory limit (SQL Server requires at least 2GB)
    add_custom_arg "--memory=2g"
    
    # Add security and privilege settings
    add_custom_arg "--user=0:0" # Run as root to avoid permission issues
    add_custom_arg "--privileged=true" # Give elevated privileges
    
    # Expose port if specified
    local expose_enabled
    expose_enabled=$(get_env "DBLAB_EXPOSE_ENABLED" "false")
    
    if [[ "$expose_enabled" == "true" ]]; then
        local expose_ports
        expose_ports=$(get_env "DBLAB_EXPOSE_PORTS" "")
        
        if [[ -n "$expose_ports" ]]; then
            # If port is specified without host port (e.g., "1433"), 
            # map it to the same host port (e.g., "1433:1433")
            if [[ "$expose_ports" =~ ^[0-9]+$ ]]; then
                expose_ports="${expose_ports}:${expose_ports}"
                log_debug "Expanded port mapping to: $expose_ports"
            fi
            add_port "$expose_ports"
        fi
    fi
    
    # Set image last
    set_image "$image"
    
    log_debug "SQL Server container configuration prepared"
}

# Wait for SQL Server to be ready
wait_for_sqlserver() {
    local container_name="$1"
    local max_attempts="${2:-60}"  # SQL Server takes longer to start
    local attempt=1
    
    log_info "Waiting for SQL Server to be ready (this may take a few minutes)..."
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Health check attempt $attempt/$max_attempts"
        
        # Use sqlcmd to check SQL Server readiness
        local sa_password version sqlcmd_path
        sa_password=$(get_env "DBLAB_SQLSERVER_SA_PASSWORD")
        version=$(get_env "DBLAB_SQLSERVER_VERSION")
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

# Create initial database
create_initial_database() {
    local container_name="$1"
    local database="$2"
    local sa_password="$3"
    
    log_info "Creating initial database: $database"
    
    # Check if database already exists
    local db_exists version sqlcmd_path
    version=$(get_env "DBLAB_SQLSERVER_VERSION")
    sqlcmd_path=$(get_sqlcmd_path "$version")

    db_exists=$(exec_container "$container_name" "$sqlcmd_path" \
        -C -S localhost -U sa -P "$sa_password" \
        -Q "SELECT DB_ID('$database')" -h -1 -W 2>/dev/null | tr -d '[:space:]' || echo "")
    
    if [[ "$db_exists" != "NULL" ]] && [[ -n "$db_exists" ]]; then
        log_debug "Database '$database' already exists"
        return 0
    fi
    
    # Create database
    local create_sql="CREATE DATABASE [$database];"

    if exec_container "$container_name" "$sqlcmd_path" \
        -C -S localhost -U sa -P "$sa_password" \
        -Q "$create_sql" >/dev/null 2>&1; then
        log_info "Database '$database' created successfully"
    else
        log_error "Failed to create database '$database'"
        return 1
    fi
}

# Start SQL Server instance
sqlserver_up() {
    local instance="$1"
    local env_files=("${@:2}")
    
    log_info "Starting SQL Server instance: $instance"
    
    # Initialize runner first
    init_runner
    
    # Load environment
    load_environment "$METADATA_FILE" "${env_files[@]}"
    validate_required_env "DBLAB_SQLSERVER_VERSION" "DBLAB_SQLSERVER_SA_PASSWORD" "DBLAB_SQLSERVER_DATABASE"
    validate_sqlserver_env
    
    local container_name
    container_name=$(get_container_name "$ENGINE_NAME" "$instance")
    
    # Check if container is already running
    if container_running "$container_name"; then
        log_info "Container is already running: $container_name"
        return 0
    fi
    
    # Check if instance exists
    local instance_exists=false
    if instance_exists "$ENGINE_NAME" "$instance"; then
        log_debug "Loading existing instance: $instance"
        load_instance "$ENGINE_NAME" "$instance"
        instance_exists=true
    else
        log_debug "Creating new instance: $instance"
        
        # Create new instance
        local version sa_password database network_mode ephemeral
        version=$(get_env "DBLAB_SQLSERVER_VERSION")
        sa_password=$(get_env "DBLAB_SQLSERVER_SA_PASSWORD")
        database=$(get_env "DBLAB_SQLSERVER_DATABASE")
        network_mode=$(get_env "DBLAB_NETWORK_MODE" "isolated")
        ephemeral=$(get_env "DBLAB_EPHEMERAL" "false")
        
        create_instance "$ENGINE_NAME" "$instance" "$version" "sa" "$sa_password" "$database" "$network_mode" "$ephemeral"
        load_instance "$ENGINE_NAME" "$instance"
    fi
    
    # Get instance configuration
    local data_dir network_name image
    data_dir=$(get_instance_config "data_dir")
    network_name=$(get_instance_config "name" "")  # network name from instance config
    if [[ -z "$network_name" ]]; then
        # Fallback: generate network name from instance info
        local network_mode
        network_mode=$(get_instance_config "mode" "isolated")
        network_name=$(get_network_name "$ENGINE_NAME" "$instance" "$network_mode")
    fi
    image=$(get_instance_config "image")
    
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
    
    # Prepare and run container
    prepare_sqlserver_container "$instance" "$network_name" "$data_dir"
    
    log_info "Starting SQL Server container: $container_name"
    run_container
    
    # Wait for SQL Server to be ready
    if ! wait_for_sqlserver "$container_name"; then
        log_error "SQL Server startup failed"
        
        # Show logs for debugging
        log_error "Container logs:"
        get_container_logs "$container_name" 50
        
        # Stop and remove failed container
        stop_container "$container_name"
        remove_container "$container_name" true
        
        die "SQL Server startup failed"
    fi
    
    # Create initial database if specified
    local database sa_password
    database=$(get_env "DBLAB_SQLSERVER_DATABASE")
    sa_password=$(get_env "DBLAB_SQLSERVER_SA_PASSWORD")
    
    if [[ "$database" != "master" ]]; then
        create_initial_database "$container_name" "$database" "$sa_password"
    fi
    
    # Update instance state
    update_instance_state "$ENGINE_NAME" "$instance" "last_up" ""
    update_instance_state "$ENGINE_NAME" "$instance" "status" "running"
    
    log_info "SQL Server instance '$instance' started successfully"
    
    # Show connection information
    local port
    port=$(get_instance_config "port")
    log_info "Connection details:"
    log_info "  Host: $container_name (in network: $network_name)"
    log_info "  Port: $port"
    log_info "  Database: $(get_instance_config "database")"
    log_info "  User: sa"
    log_info "  Note: Use the SA password you configured"
}

# Stop SQL Server instance
sqlserver_down() {
    local instance="$1"
    
    log_info "Stopping SQL Server instance: $instance"
    
    # Initialize runner
    init_runner
    
    local container_name
    container_name=$(get_container_name "$ENGINE_NAME" "$instance")
    
    # Check if container is running
    if ! container_running "$container_name"; then
        log_info "Container is not running: $container_name"
        return 0
    fi
    
    # Stop container gracefully
    log_info "Stopping container: $container_name"
    stop_container "$container_name" 60  # 60 second timeout for SQL Server
    
    # Remove container
    remove_container "$container_name"
    
    # Update instance state if instance exists
    if instance_exists "$ENGINE_NAME" "$instance"; then
        update_instance_state "$ENGINE_NAME" "$instance" "last_down" ""
        update_instance_state "$ENGINE_NAME" "$instance" "status" "stopped"
    fi
    
    log_info "SQL Server instance '$instance' stopped successfully"
}

# Get SQL Server instance status
sqlserver_status() {
    local instance="$1"
    
    init_runner
    
    local container_name
    container_name=$(get_container_name "$ENGINE_NAME" "$instance")
    
    local status
    status=$(get_container_status "$container_name")
    
    echo "$status"
}

# Destroy SQL Server instance (remove everything)
sqlserver_destroy() {
    local instance="$1"
    
    log_info "Destroying SQL Server instance: $instance"
    
    # Initialize runner
    init_runner
    
    # Check if instance exists
    if ! instance_exists "$ENGINE_NAME" "$instance"; then
        log_warn "Instance does not exist: $instance"
        return 0
    fi
    
    # Load instance configuration
    load_instance "$ENGINE_NAME" "$instance"
    
    local container_name network_name data_dir
    container_name=$(get_container_name "$ENGINE_NAME" "$instance")
    data_dir=$(get_instance_config "data_dir")
    
    # Get network name from config
    local network_mode
    network_mode=$(get_instance_config "mode" "isolated")
    network_name=$(get_network_name "$ENGINE_NAME" "$instance" "$network_mode")
    
    # Stop and remove container if running/exists
    if container_exists "$container_name"; then
        if container_running "$container_name"; then
            log_info "Stopping running container: $container_name"
            stop_container "$container_name" 60
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
    
    # Ask for confirmation before removing data
    local remove_data="false"
    local ephemeral
    ephemeral=$(get_instance_config "ephemeral" "false")
    
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
            
            # SQL Server containers may create files as root/mssql user
            # Use container runtime to remove files with proper permissions
            if command_exists "${DBLAB_CONTAINER_RUNTIME}"; then
                log_debug "Using container runtime to remove data with proper permissions"
                local temp_container="dblab-cleanup-$(date +%s)"
                local sqlserver_version
                sqlserver_version=$(get_instance_config "version" "2022-latest")
                
                # Run a temporary container to clean up with proper permissions
                "${DBLAB_CONTAINER_RUNTIME}" run --rm \
                    -v "${data_dir}:/data" \
                    --name "$temp_container" \
                    "mcr.microsoft.com/mssql/server:${sqlserver_version}" \
                    sh -c "rm -rf /data/*" 2>/dev/null || true
                
                # Remove the now-empty directory
                rmdir "$data_dir" 2>/dev/null || safe_rm "$data_dir"
            else
                # Fallback: try to change permissions first, then remove
                log_warn "Container runtime not available, trying to change permissions"
                if command_exists sudo; then
                    sudo chown -R "$(whoami)" "$data_dir" 2>/dev/null || true
                fi
                safe_rm "$data_dir"
            fi
        fi
    else
        log_info "Data directory preserved: $data_dir"
    fi
    
    # Remove instance configuration
    log_info "Removing instance configuration"
    remove_instance "$ENGINE_NAME" "$instance" true  # Force removal
    
    log_info "SQL Server instance '$instance' destroyed successfully"
    
    if [[ "$remove_data" == "false" ]]; then
        log_info "Note: Data was preserved and can be reused by creating a new instance"
        log_info "      with the same name and configuration."
    fi
}

# Main command dispatcher
main() {
    local command="$1"
    local instance="$2"
    shift 2
    local args=("$@")
    
    case "$command" in
        up)
            sqlserver_up "$instance" "${args[@]}"
            ;;
        down)
            sqlserver_down "$instance"
            ;;
        status)
            sqlserver_status "$instance"
            ;;
        destroy)
            sqlserver_destroy "$instance"
            ;;
        *)
            die "Unknown SQL Server command: $command"
            ;;
    esac
}

# Export functions for testing
export -f validate_sqlserver_env prepare_sqlserver_container wait_for_sqlserver
export -f create_initial_database sqlserver_up sqlserver_down sqlserver_status sqlserver_destroy

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
