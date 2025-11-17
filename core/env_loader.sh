#!/bin/bash

# core/env_loader.sh - Environment variable loading with priority layers
# This module handles the 5-layer config priority system described in SPEC.md

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"

# Environment loading configuration
declare -A ENV_LAYERS=(
    [core]=1
    [metadata]=2
    [env_files]=3
    [environment]=4
    [cli]=5
)

# Temporary storage for resolved environment
declare -A RESOLVED_ENV=()
declare -A ENV_SOURCES=()  # Track where each value came from

# Core default values (layer 1)
set_core_defaults() {
    log_trace "Setting core default values"
    
    # Global defaults
    RESOLVED_ENV[DBLAB_LOG_LEVEL]="${DBLAB_LOG_LEVEL:-info}"
    RESOLVED_ENV[DBLAB_BASE_DIR]="${DBLAB_BASE_DIR:-${HOME}/.local/share/dblab}"
    RESOLVED_ENV[DBLAB_EPHEMERAL]="${DBLAB_EPHEMERAL:-false}"
    
    # Mark sources
    ENV_SOURCES[DBLAB_LOG_LEVEL]="core"
    ENV_SOURCES[DBLAB_BASE_DIR]="core"
    ENV_SOURCES[DBLAB_EPHEMERAL]="core"
    
    log_trace "Core defaults set"
}

# Load engine metadata defaults (layer 2)
load_metadata_defaults() {
    local metadata_file="$1"
    
    log_trace "Attempting to load metadata from: $metadata_file"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_warn "Metadata file not found: $metadata_file"
        return 0
    fi
    
    log_trace "Loading metadata defaults from: $metadata_file"
    
    # Simple YAML parsing for defaults section
    local in_defaults=false
    while IFS= read -r line; do
        # Remove leading whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//')
        
        # Check if we're in defaults section
        if [[ "$line" == "defaults:" ]]; then
            in_defaults=true
            continue
        fi
        
        # End of defaults section
        if [[ "$line" =~ ^[a-zA-Z] && "$line" != "defaults:" ]]; then
            in_defaults=false
        fi
        
        # Parse key-value pairs in defaults section
        if [[ "$in_defaults" == true && "$line" =~ ^([A-Z_]+):[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            value=$(echo "$value" | sed 's/^"//;s/"$//')
            
            log_trace "Setting metadata default: $key=$value"
            RESOLVED_ENV[$key]="$value"
            ENV_SOURCES[$key]="metadata"
        fi
    done < "$metadata_file"
    
    log_trace "Metadata defaults loaded"
}

# Load environment files (layer 3)
load_env_files() {
    local env_files=("$@")
    
    for env_file in "${env_files[@]}"; do
        if [[ ! -f "$env_file" ]]; then
            log_warn "Environment file not found: $env_file"
            continue
        fi
        
        log_trace "Loading environment file: $env_file"
        
        while IFS= read -r line; do
            # Skip empty lines and comments
            if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
                continue
            fi
            
            # Parse KEY=VALUE format
            if [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                
                # Remove quotes if present
                value=$(echo "$value" | sed 's/^"//;s/"$//;s/^'\''//;s/'\''$//')
                
                log_trace "Setting env file value: $key=$(mask_sensitive "$value")"
                RESOLVED_ENV[$key]="$value"
                ENV_SOURCES[$key]="env_file:$env_file"
            fi
        done < "$env_file"
    done
    
    log_trace "Environment files loaded"
}

# Load host environment variables (layer 4)
load_host_environment() {
    log_trace "Loading host environment variables"
    
    # Get all DBLAB_* variables from environment
    while IFS= read -r line; do
        if [[ "$line" =~ ^(DBLAB_[A-Z_]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            log_trace "Setting host env value: $key=$(mask_sensitive "$value")"
            RESOLVED_ENV[$key]="$value"
            ENV_SOURCES[$key]="host_env"
        fi
    done < <(env | grep "^DBLAB_" || true)
    
    log_trace "Host environment loaded"
}

# Apply CLI overrides (layer 5)
apply_cli_overrides() {
    local overrides=("$@")
    
    log_trace "Applying CLI overrides"
    
    for override in "${overrides[@]}"; do
        if [[ "$override" =~ ^([A-Z_]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            log_trace "Setting CLI override: $key=$(mask_sensitive "$value")"
            RESOLVED_ENV[$key]="$value"
            ENV_SOURCES[$key]="cli"
        fi
    done
    
    log_trace "CLI overrides applied"
}

# Validate required environment variables
validate_required_env() {
    local required_vars=("$@")
    local missing_vars=()
    
    log_trace "Validating required environment variables"
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${RESOLVED_ENV[$var]:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        die "Environment validation failed"
    fi
    
    log_trace "Environment validation passed"
}

# Validate required environment variables using metadata file (enhanced version)
validate_required_env_with_metadata() {
    local metadata_file="$1"
    local env_prefix="$2"
    
    log_trace "Validating required environment variables using metadata: $metadata_file"
    
    # Source validator.sh if not already loaded
    if ! command -v validate_env_against_metadata >/dev/null 2>&1; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        source "${SCRIPT_DIR}/validator.sh"
    fi
    
    # Use metadata-driven validation
    if ! validate_env_against_metadata "$metadata_file" "$env_prefix"; then
        die "Environment validation failed against metadata"
    fi
    
    log_trace "Metadata-driven environment validation passed"
}

# Export resolved environment to current shell
export_resolved_env() {
    local export_sensitive="${1:-false}"
    
    log_trace "Exporting resolved environment"
    
    for key in "${!RESOLVED_ENV[@]}"; do
        local value="${RESOLVED_ENV[$key]}"
        
        # Skip sensitive values unless explicitly requested
        if [[ "$export_sensitive" == "false" && "$key" =~ PASSWORD|TOKEN|SECRET ]]; then
            log_trace "Skipping sensitive variable: $key"
            continue
        fi
        
        export "$key=$value"
        log_trace "Exported: $key=$(mask_sensitive "$value") [source: ${ENV_SOURCES[$key]}]"
    done
}

# Get resolved environment value
get_env() {
    local key="$1"
    local default="${2:-}"
    
    echo "${RESOLVED_ENV[$key]:-$default}"
}

# Get environment value source
get_env_source() {
    local key="$1"
    echo "${ENV_SOURCES[$key]:-unknown}"
}

# Show environment resolution details for diagnostics
show_env_resolution() {
    local show_sensitive="${1:-false}"
    
    log_info "Environment Resolution Details:"
    log_info "================================"
    
    for key in $(printf '%s\n' "${!RESOLVED_ENV[@]}" | sort); do
        local value="${RESOLVED_ENV[$key]}"
        local source="${ENV_SOURCES[$key]}"
        
        if [[ "$show_sensitive" == "false" && "$key" =~ PASSWORD|TOKEN|SECRET ]]; then
            value="****"
        fi
        
        printf "%-30s = %-20s [%s]\n" "$key" "$value" "$source"
    done
}

# Main environment loading function
load_environment() {
    local metadata_file="${1:-}"
    shift || true
    local env_files=("$@")
    local cli_overrides=()
    
    log_debug "Starting environment loading process"
    log_trace "Metadata file: $metadata_file"
    log_trace "Environment files: ${env_files[*]:-none}"
    
    # Clear previous state
    RESOLVED_ENV=()
    ENV_SOURCES=()
    
    # Load each layer in order
    set_core_defaults
    
    if [[ -n "$metadata_file" ]]; then
        load_metadata_defaults "$metadata_file"
    fi
    
    if [[ ${#env_files[@]} -gt 0 ]]; then
        load_env_files "${env_files[@]}"
    fi
    
    load_host_environment
    
    # CLI overrides would be applied by caller
    # apply_cli_overrides "${cli_overrides[@]}"
    
    log_debug "Environment loading completed"
}

# Reset environment state
reset_environment() {
    RESOLVED_ENV=()
    ENV_SOURCES=()
    log_trace "Environment state reset"
}

# Export functions for use by other modules
export -f load_environment reset_environment get_env get_env_source
export -f validate_required_env validate_required_env_with_metadata export_resolved_env show_env_resolution
export -f apply_cli_overrides
