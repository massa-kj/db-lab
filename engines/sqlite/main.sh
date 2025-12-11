#!/bin/bash

# engines/sqlite/main.sh - SQLite engine main operations
# Handles SQLite container lifecycle (up/down/status) and database file management

set -euo pipefail

# Source core utilities
SQLITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SQLITE_DIR}/../../core"
source "${CORE_DIR}/lib.sh"
source "${CORE_DIR}/runner.sh"
source "${CORE_DIR}/network.sh"
source "${CORE_DIR}/validator.sh"

# Source engine-specific validators
source "${SQLITE_DIR}/validator.sh"
# Register SQLite-specific validation rules
sqlite_register_validation_rules

# Engine-specific configuration
readonly ENGINE_NAME="sqlite"

# Check if sqlite3 command is available on host
check_host_sqlite() {
    if command -v sqlite3 >/dev/null 2>&1; then
        log_debug "Host sqlite3 command found"
        return 0
    else
        log_debug "Host sqlite3 command not found"
        return 1
    fi
}

# Initialize SQLite database with pragmas directly on host
init_sqlite_database_host() {
    local db_file_path="$1"
    local journal_mode="$2"
    local foreign_keys="$3"
    local timeout="$4"
    
    log_debug "Initializing SQLite database on host: $db_file_path"
    
    # Create directory if it doesn't exist
    local db_dir
    db_dir=$(dirname "$db_file_path")
    mkdir -p "$db_dir"
    
    # Initialize database file if it doesn't exist and apply pragmas
    local init_sql="
PRAGMA journal_mode=$journal_mode;
PRAGMA foreign_keys=$foreign_keys;
PRAGMA busy_timeout=$timeout;
-- Create a simple metadata table to ensure database is initialized
CREATE TABLE IF NOT EXISTS _dblab_metadata (
    key TEXT PRIMARY KEY,
    value TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
INSERT OR REPLACE INTO _dblab_metadata (key, value) VALUES ('initialized', 'true');
INSERT OR REPLACE INTO _dblab_metadata (key, value) VALUES ('engine', 'sqlite');
INSERT OR REPLACE INTO _dblab_metadata (key, value) VALUES ('last_started', datetime('now'));
"
    
    # Execute initialization SQL using host sqlite3
    if echo "$init_sql" | sqlite3 "$db_file_path"; then
        log_debug "SQLite database initialized successfully on host"
        return 0
    else
        log_error "Failed to initialize SQLite database on host"
        return 1
    fi
}

# Initialize SQLite database with pragmas
init_sqlite_database() {
    local container_name="$1"
    local db_file_path="$2"
    local journal_mode="$3"
    local foreign_keys="$4"
    local timeout="$5"
    
    log_debug "Initializing SQLite database: $db_file_path"
    
    # Initialize database file if it doesn't exist and apply pragmas
    local init_sql="
PRAGMA journal_mode=$journal_mode;
PRAGMA foreign_keys=$foreign_keys;
PRAGMA busy_timeout=$timeout;
-- Create a simple metadata table to ensure database is initialized
CREATE TABLE IF NOT EXISTS _dblab_metadata (
    key TEXT PRIMARY KEY,
    value TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
INSERT OR REPLACE INTO _dblab_metadata (key, value) VALUES ('initialized', 'true');
INSERT OR REPLACE INTO _dblab_metadata (key, value) VALUES ('engine', 'sqlite');
INSERT OR REPLACE INTO _dblab_metadata (key, value) VALUES ('last_started', datetime('now'));
"
    
    # Execute initialization SQL
    if exec_container "$container_name" sqlite3 "$db_file_path" <<< "$init_sql"; then
        log_debug "SQLite database initialized successfully"
    else
        log_error "Failed to initialize SQLite database"
        return 1
    fi
}

# Check if SQLite database file exists and is accessible
check_sqlite_database() {
    local container_name="$1"
    local db_file_path="$2"
    
    # Check if database file exists and is accessible
    if exec_container "$container_name" test -f "$db_file_path" 2>/dev/null; then
        # Try to query the database
        if exec_container "$container_name" sqlite3 "$db_file_path" \
            "SELECT 1;" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Wait for SQLite container to be ready
wait_for_sqlite() {
    local container_name="$1"
    local db_file_path="$2"
    local max_attempts="${3:-30}"
    local attempt=1
    
    log_info "Waiting for SQLite container to be ready..."
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Health check attempt $attempt/$max_attempts"
        
        # Check if container is running and sqlite3 command is available
        if exec_container "$container_name" sqlite3 --version >/dev/null 2>&1; then
            log_info "SQLite container is ready!"
            return 0
        fi
        
        log_debug "SQLite container not ready yet, waiting..."
        sleep 2
        ((attempt++))
    done
    
    log_error "SQLite container failed to become ready within $((max_attempts * 2)) seconds"
    return 1
}

# Start SQLite instance
engine_up() {
    local -n C="$1"
    
    local engine="${C[engine]}"
    local instance="${C[instance]}"
    
    log_info "Starting SQLite instance: $instance"
    
    # Get SQLite configuration
    local journal_mode="${C[sqlite.journal_mode]:-WAL}"
    local foreign_keys="${C[sqlite.foreign_keys]:-ON}"
    local timeout="${C[sqlite.timeout]:-30000}"
    local data_dir="${C[storage.data_dir]:-${XDG_DATA_HOME:-$HOME/.local/share}/dblab/sqlite/${instance}/data}"
    local db_file_path_container="${C[db.file_path]}"
    
    # Convert container path to host path
    local db_file_path_host="${data_dir}/${instance}${C[db.file_extension]:-.sqlite}"
    
    # Ensure data directory exists
    ensure_dir "$data_dir"
    
    # Try to initialize database on host first
    if check_host_sqlite; then
        log_info "Using host sqlite3 command to create database"
        if init_sqlite_database_host "$db_file_path_host" "$journal_mode" "$foreign_keys" "$timeout"; then
            # Update instance state
            update_state_up "$engine" "$instance"
            
            log_info "SQLite instance '$instance' started successfully"
            log_info "Database information:"
            log_info "  File: ${db_file_path_host}"
            log_info "  Database: ${C[db.database]}"
            log_info "  Journal mode: $journal_mode"
            log_info "  Foreign keys: $foreign_keys"
            return 0
        else
            log_warn "Failed to initialize database on host, falling back to container"
        fi
    else
        log_info "Host sqlite3 command not found, using container fallback"
    fi
    
    # Fallback: Use container for database initialization
    log_info "Using container to create SQLite database"
    
    # Initialize runner
    init_runner
    
    local container_name
    container_name=$(get_container_name "$engine" "$instance")
    
    # Check if container is already running
    if container_running "$container_name"; then
        log_info "Container is already running: $container_name"
        return 0
    fi
    
    # Get network configuration
    local network_name="${C[network.name]:-}"
    if [[ -z "$network_name" ]]; then
        # Fallback: generate network name from instance info
        local network_mode
        network_mode="${C[network.mode]:-isolated}"
        network_name=$(get_network_name "$engine" "$instance" "$network_mode")
    fi
    local image="${C[image]}"
    
    # Create network if it doesn't exist
    create_network "$network_name"
    
    # Ensure image is available
    ensure_image "$image"
    
    # Remove existing stopped container if exists
    if container_exists "$container_name" && ! container_running "$container_name"; then
        log_debug "Removing existing stopped container: $container_name"
        remove_container "$container_name"
    fi
    
    log_info "Starting temporary SQLite container for database initialization: $container_name"
    
    # Build command arguments for temporary container
    local run_args=(
        "--name" "${container_name}"
        "--network" "${network_name}"
        "-d"
        # Mount data directory to /data in container
        "-v" "${data_dir}:/data"
    )
    
    # Run container with infinite loop to keep it alive temporarily
    # Install sqlite3 and then keep container running
    runner_run "${image}" "${run_args[@]}" sh -c "apk add --no-cache sqlite && while true; do sleep 3600; done"
    
    # Wait for SQLite container to be ready
    if ! wait_for_sqlite "$container_name" "$db_file_path_container" 30; then
        log_error "SQLite container startup failed"
        
        # Show logs for debugging
        log_error "Container logs:"
        get_container_logs "$container_name" 50
        
        # Stop and remove failed container
        stop_container "$container_name"
        remove_container "$container_name" true
        
        die "SQLite container startup failed"
    fi
    
    # Initialize SQLite database in container
    if ! init_sqlite_database "$container_name" "$db_file_path_container" "$journal_mode" "$foreign_keys" "$timeout"; then
        # Stop and remove container after initialization
        stop_container "$container_name"
        remove_container "$container_name" true
        die "Failed to initialize SQLite database"
    fi
    
    # Fix permissions for the created database file
    log_debug "Fixing permissions for database file"
    if ! exec_container "$container_name" chown "$(id -u):$(id -g)" "$db_file_path_container" 2>/dev/null; then
        log_warn "Could not change ownership of database file (this may be normal)"
    fi
    
    # Stop and remove the temporary container after initialization
    log_info "Database initialized, stopping temporary container"
    stop_container "$container_name"
    remove_container "$container_name" true
    
    # Fix permissions on host if needed
    if [[ -f "$db_file_path_host" ]]; then
        if ! [[ -r "$db_file_path_host" && -w "$db_file_path_host" ]]; then
            log_info "Fixing database file permissions on host"
            if command -v sudo >/dev/null 2>&1; then
                sudo chown "$(id -u):$(id -g)" "$db_file_path_host" 2>/dev/null || log_warn "Could not fix file permissions"
            fi
        fi
    fi
    
    # Update instance state
    update_state_up "$engine" "$instance"
    
    log_info "SQLite instance '$instance' started successfully"
    
    # Show connection information
    log_info "Database information:"
    log_info "  File: ${db_file_path_host}"
    log_info "  Database: ${C[db.database]}"
    log_info "  Journal mode: $journal_mode"
    log_info "  Foreign keys: $foreign_keys"
}

# Connect to SQLite CLI
engine_cli() {
    local -n C="$1"
    shift  # Remove first argument (config reference)

    # Get instance from FINAL_CONFIG (should be set by command_dispatcher)
    local instance="${C[instance]:-}"
    
    if [[ -z "$instance" ]]; then
        log_error "Instance name is required for CLI connection"
        return 1
    fi
    
    local engine="${C[engine]}"
    local use_container="${C[sqlite.use_container]:-false}"
    
    log_debug "CLI connecting to instance: $instance (engine: $engine, use_container: $use_container)"
    
    # Get database file path
    local data_dir="${C[storage.data_dir]:-${XDG_DATA_HOME:-$HOME/.local/share}/dblab/sqlite/${instance}/data}"
    local db_file_path_host="${data_dir}/${instance}${C[db.file_extension]:-.sqlite}"
    
    # Convert {instance} placeholder in container path
    local db_file_path_container="${C[db.file_path]}"
    db_file_path_container="${db_file_path_container//\{instance\}/$instance}"
    
    if [[ "$use_container" == "false" ]]; then
        # Use host sqlite3 command
        if check_host_sqlite; then
            log_info "Using host sqlite3 command"
            
            # Check if database file exists
            if [[ ! -f "$db_file_path_host" ]]; then
                log_error "Database file not found: $db_file_path_host"
                log_error "Please run 'dblab up sqlite --instance $instance' first"
                return 1
            fi
            
            # Execute sqlite3 directly on host
            if [[ $# -eq 0 ]]; then
                # Interactive mode
                sqlite3 "$db_file_path_host"
            else
                # Non-interactive mode with arguments
                sqlite3 "$db_file_path_host" "$@"
            fi
            return $?
        else
            log_error "Host sqlite3 command not found"
            log_error "Please install sqlite3 on the host or set DBLAB_SQLITE_USE_CONTAINER=true"
            log_error "Install command (Ubuntu/Debian): sudo apt-get install sqlite3"
            log_error "Install command (RHEL/CentOS): sudo yum install sqlite"
            log_error "Install command (macOS): brew install sqlite"
            return 1
        fi
    fi
    
    # Use container for CLI
    log_info "Using container for SQLite CLI"
    
    # Initialize runner
    init_runner
    
    # Get SQLite container name to connect to
    local sqlite_container
    sqlite_container=$(get_container_name "$engine" "$instance")

    local BEFORE=()
    local AFTER=()
    
    local cli_container="${sqlite_container}_cli"

    # CLI image (should be the same as main image for SQLite)
    local cli_image="${C[cli_image]}"

    local network_name
    network_name="${C[network.name]:-}"
    if [[ -z "$network_name" ]]; then
        # Fallback: generate network name from instance info
        local network_mode
        network_mode="${C[network.mode]:-isolated}"
        network_name=$(get_network_name "$engine" "$instance" "$network_mode")
    fi

    # Check if this is non-interactive mode (has specific commands)
    local use_interactive=true
    for arg in "$@"; do
        if [[ "$arg" == ".quit" || "$arg" =~ ^[.].*$ ]]; then
            use_interactive=false
            break
        fi
    done
    
    BEFORE+=("--name=${cli_container}")
    BEFORE+=("--rm")
    BEFORE+=("--network=${network_name}")
    # Mount the data directory directly
    BEFORE+=("-v" "${data_dir}:/data")
    if [[ "$use_interactive" == "true" ]]; then
        BEFORE+=("--interactive")
        BEFORE+=("--tty")
    fi
    
    AFTER+=("${C[cli_command]}")
    AFTER+=("${db_file_path_container}")
    
    # Pass through all additional arguments
    for arg in "$@"; do
        AFTER+=("$arg")
    done
    
    # Install sqlite3 in the CLI container before running command
    runner_run2 "${cli_image}" --before "${BEFORE[@]}" --after sh -c "apk add --no-cache sqlite && ${AFTER[*]}"
}

# Execute SQL script or command
engine_exec() {
    local -n C="$1"
    shift  # Remove first argument (config reference)

    # Get instance from FINAL_CONFIG (should be set by command_dispatcher)
    local instance="${C[instance]:-}"
    
    if [[ -z "$instance" ]]; then
        log_error "Instance name is required for exec operation"
        return 1
    fi
    
    local engine="${C[engine]}"
    local use_container="${C[sqlite.use_container]:-false}"
    
    # Get database file path
    local data_dir="${C[storage.data_dir]:-${XDG_DATA_HOME:-$HOME/.local/share}/dblab/sqlite/${instance}/data}"
    local db_file_path_host="${data_dir}/${instance}${C[db.file_extension]:-.sqlite}"
    
    # Expand the file path placeholder manually
    local db_file_path_container="${C[db.file_path]}"
    db_file_path_container="${db_file_path_container//'{instance}'/$instance}"
    
    if [[ "$use_container" == "false" ]]; then
        # Use host sqlite3 command
        if check_host_sqlite; then
            log_debug "Using host sqlite3 command for exec"
            
            # Check if database file exists
            if [[ ! -f "$db_file_path_host" ]]; then
                log_error "Database file not found: $db_file_path_host"
                log_error "Please run 'dblab up sqlite --instance $instance' first"
                return 1
            fi
            
            # Execute SQL script or command on host
            if [[ $# -eq 0 ]]; then
                # Read from stdin and pipe to sqlite3
                sqlite3 "$db_file_path_host"
            else
                # Execute provided command/script
                sqlite3 "$db_file_path_host" "$@"
            fi
            return $?
        else
            log_error "Host sqlite3 command not found"
            log_error "Please install sqlite3 on the host or set DBLAB_SQLITE_USE_CONTAINER=true"
            return 1
        fi
    fi
    
    # Use container for exec
    log_debug "Using container for SQLite exec"
    
    # Initialize runner
    init_runner
    
    # Get SQLite container name
    local sqlite_container
    sqlite_container=$(get_container_name "$engine" "$instance")
    
    # Execute SQL script or command
    if [[ $# -eq 0 ]]; then
        # Read from stdin and pipe to container
        local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
        "$runtime" exec -i "$sqlite_container" sqlite3 "$db_file_path_container"
    else
        # Execute provided command/script
        exec_container "$sqlite_container" sqlite3 "$db_file_path_container" "$@"
    fi
}

# Export functions for testing
export -f check_host_sqlite init_sqlite_database_host init_sqlite_database check_sqlite_database wait_for_sqlite engine_up engine_cli engine_exec
