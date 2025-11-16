#!/bin/bash

# core/env_template.sh - Environment template generation
# Generates template .env files from engine metadata

set -euo pipefail

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"

# Generate environment template from metadata.yml
generate_env_template() {
    local engine="$1"
    local instance="$2"
    local metadata_file="$3"
    
    if [[ ! -f "$metadata_file" ]]; then
        die "Metadata file not found: $metadata_file"
    fi
    
    log_debug "Generating environment template for $engine instance: $instance"
    
    echo "# Environment template for $engine instance: $instance"
    echo "# Generated on $(date)"
    echo "# Usage: dblab up $engine --instance $instance --env-file ${instance}.env"
    echo ""
    
    # Parse metadata
    local required_env defaults
    required_env=$(parse_yaml_array "$metadata_file" "required_env")
    defaults=$(parse_yaml_section "$metadata_file" "defaults")
    
    echo "# ==========================="
    echo "# REQUIRED ENVIRONMENT VARIABLES"
    echo "# ==========================="
    echo ""
    
    # Generate required env vars
    while IFS= read -r env_var; do
        [[ -z "$env_var" ]] && continue
        
        local default_value=""
        if echo "$defaults" | grep -q "^${env_var}="; then
            default_value=$(echo "$defaults" | grep "^${env_var}=" | cut -d'=' -f2- | sed 's/^"\|"$//g')
        fi
        
        if [[ -n "$default_value" ]]; then
            echo "${env_var}=${default_value}"
        else
            case "$env_var" in
                *PASSWORD*)
                    echo "${env_var}=# REQUIRED: Set your password here"
                    ;;
                *USER*)
                    echo "${env_var}=# REQUIRED: Set your username here"
                    ;;
                *DATABASE*|*DB*)
                    echo "${env_var}=# REQUIRED: Set your database name here"
                    ;;
                *VERSION*)
                    echo "${env_var}=# REQUIRED: Set your version (e.g., 16, latest)"
                    ;;
                *)
                    echo "${env_var}=# REQUIRED: Set this value"
                    ;;
            esac
        fi
        echo ""
    done <<< "$required_env"
    
    echo "# ==========================="
    echo "# OPTIONAL ENVIRONMENT VARIABLES"
    echo "# ==========================="
    echo ""
    
    # Generate optional env vars from defaults
    while IFS= read -r default_line; do
        [[ -z "$default_line" ]] && continue
        
        local env_var value
        env_var=$(echo "$default_line" | cut -d'=' -f1)
        value=$(echo "$default_line" | cut -d'=' -f2- | sed 's/^"\|"$//g')
        
        # Skip if already in required
        if echo "$required_env" | grep -q "^${env_var}$"; then
            continue
        fi
        
        echo "# ${env_var}=${value}"
        echo ""
    done <<< "$defaults"
    
    echo "# ==========================="
    echo "# INSTANCE METADATA (READ-ONLY)"
    echo "# ==========================="
    echo "# These values will be saved to instance.yml after creation"
    echo "# and cannot be changed via env file after instance creation"
    echo ""
    echo "# DBLAB_INSTANCE=${instance}"
    echo "# DBLAB_ENGINE=${engine}"
    echo "# DBLAB_CREATED=$(date -I)"
    echo ""
    echo "# Network configuration"
    echo "# DBLAB_NETWORK_MODE=isolated  # isolated or engine-shared"
    echo ""
    echo "# Data persistence"
    echo "# DBLAB_EPHEMERAL=false  # true for temporary data"
}

# Validate env file against metadata requirements
validate_env_file() {
    local env_file="$1"
    local metadata_file="$2"
    
    if [[ ! -f "$env_file" ]]; then
        die "Environment file not found: $env_file"
    fi
    
    if [[ ! -f "$metadata_file" ]]; then
        die "Metadata file not found: $metadata_file"
    fi
    
    local required_env missing_vars=()
    required_env=$(parse_yaml_array "$metadata_file" "required_env")
    
    log_debug "Validating environment file: $env_file"
    
    while IFS= read -r env_var; do
        [[ -z "$env_var" ]] && continue
        
        # Check if variable is set in env file
        if ! grep -q "^${env_var}=" "$env_file" 2>/dev/null; then
            missing_vars+=("$env_var")
        else
            # Check if variable has a value (not empty or comment)
            local value
            value=$(grep "^${env_var}=" "$env_file" | head -1 | cut -d'=' -f2- | sed 's/^[ \t]*//')
            if [[ -z "$value" || "$value" =~ ^#.* ]]; then
                missing_vars+=("$env_var (empty or commented)")
            fi
        fi
    done <<< "$required_env"
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing or empty required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        log_error ""
        log_error "Please set these variables in: $env_file"
        log_error "Use 'dblab init <engine> --instance <name>' to generate a template"
        return 1
    fi
    
    log_debug "Environment validation successful"
    return 0
}

# Export functions
export -f generate_env_template validate_env_file
