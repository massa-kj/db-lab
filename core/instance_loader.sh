#!/bin/bash

# core/instance_loader.sh - Instance metadata management
# Handles instance.yml files for persistent instance configuration

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"

# Instance state structure
declare -A INSTANCE_CONFIG=()

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

# Create new instance configuration
create_instance() {
    local engine="$1"
    local instance="$2"
    local version="$3"
    local user="$4"
    local password="$5"
    local database="$6"
    local network_mode="${7:-isolated}"
    local ephemeral="${8:-false}"
    local port="${9:-}"
    
    validate_engine_name "$engine"
    validate_instance_name "$instance"
    
    if instance_exists "$engine" "$instance"; then
        die "Instance already exists: $engine/$instance"
    fi
    
    log_info "Creating new instance: $engine/$instance"
    
    # Create instance directory
    local data_dir
    data_dir=$(get_data_dir "$engine" "$instance")
    ensure_dir "$data_dir"
    ensure_dir "${data_dir}/data"
    ensure_dir "${data_dir}/config"
    ensure_dir "${data_dir}/logs"
    
    # Generate instance configuration
    local container_name
    container_name=$(get_container_name "$engine" "$instance")
    
    local network_name
    network_name=$(get_network_name "$engine" "$instance" "$network_mode")
    
    # Generate image name based on engine and version
    local image
    case "$engine" in
        postgres) image="postgres:${version}" ;;
        mysql) image="mysql:${version}" ;;
        redis) image="redis:${version}" ;;
        mongodb) image="mongo:${version}" ;;
        sqlserver) image="mcr.microsoft.com/mssql/server:${version}" ;;
        *) die "Unsupported engine: $engine" ;;
    esac

    local created_timestamp
    created_timestamp=$(date -Iseconds)
    
    # Determine default port if not provided
    if [[ -z "$port" ]]; then
        case "$engine" in
            postgres) port="5432" ;;
            mysql) port="3306" ;;
            redis) port="6379" ;;
            mongodb) port="27017" ;;
            *) port="5432" ;;  # fallback
        esac
    fi
    
    # Create instance.yml file
    local instance_file
    instance_file=$(get_instance_file "$engine" "$instance")
    
    cat > "$instance_file" << EOF
# Instance configuration for $engine/$instance
# This file is managed by dblab and should not be edited manually

engine: $engine
instance: $instance
version: "$version"

network:
  mode: $network_mode
  name: $network_name

image: "$image"
created: "$created_timestamp"

# Database configuration (fixed attributes)
db:
  user: $user
  password: "$password"
  database: $database
  port: $port

# Storage configuration (fixed attributes)
storage:
  persistent: $([ "$ephemeral" = "true" ] && echo "false" || echo "true")
  data_dir: "${data_dir}/data"
  config_dir: "${data_dir}/config"
  log_dir: "${data_dir}/logs"

# Runtime configuration (changeable)
runtime:
  expose:
    enabled: false
    ports: []
  resources:
    memory: null
    cpus: null

# Internal state
state:
  container_name: $container_name
  last_up: null
  last_down: null
  status: "created"
EOF

    log_info "Instance created successfully: $instance_file"
}

# Get instance configuration value
get_instance_config() {
    local key="$1"
    local default="${2:-}"
    
    echo "${INSTANCE_CONFIG[$key]:-$default}"
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
    safe_rm "$data_dir"
    log_info "Instance removed successfully"
}

# Export functions for use by other modules
export -f instance_exists get_instance_config list_instances remove_instance get_container_name get_network_name get_instance_file

dblab_instance_load() {
    local engine="$1"
    local instance="$2"
    local -n OUT_INSTANCE="$3" # assoc-array
    local -n OUT_INSTANCE_FIXED="$4" # assoc-array

    local file
    file=$(get_instance_file "$engine" "$instance")

    if [ ! -f "$file" ]; then
        log_debug "No instance.yml found for $engine/$instance"
        return 1
    fi

    log_debug "Loading instance.yml: $file"

    # declare -A tmp=()
    yaml_parse_file "$file" OUT_INSTANCE

    _instance_extract_fixed OUT_INSTANCE OUT_INSTANCE_FIXED
    # Minimal validation of fixed attributes
    # _instance_validate_fixed_structure OUT_INSTANCE_FIXED "$engine" "$instance"

    return 0
}

# =============================================================
# Fixed Attribute Extraction
# -------------------------------------------------------------
# engine / instance / version / network.* / image / db initial attributes
# =============================================================
_instance_extract_fixed() {
    local -n RAW="$1"
    local -n OUT="$2"

    OUT[engine]="${RAW[engine]}"
    OUT[instance]="${RAW[instance]}"
    OUT[version]="${RAW[version]}"

    # network.*
    OUT[network.mode]="${RAW[network.mode]}"
    # OUT[network.name]="${RAW[network.name]}"

    OUT[image]="${RAW[image]}"

    # db.*
    OUT[db.user]="${RAW[db.user]}"
    OUT[db.password]="${RAW[db.password]}"
    OUT[db.database]="${RAW[db.database]}"
    OUT[db.port]="${RAW[db.port]}"

    # storage.*
    OUT[storage.persistent]="${RAW[storage.persistent]}"
    OUT[storage.data_dir]="${RAW[storage.data_dir]}"
    OUT[storage.config_dir]="${RAW[storage.config_dir]}"
    OUT[storage.log_dir]="${RAW[storage.log_dir]}"
}
