#!/usr/bin/env bash

# core/env_template.sh - Environment template generation
# Generates template .env files from engine metadata

set -euo pipefail

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# Generate environment template from FINAL_CONFIG
generate_env_template() {
    local -n C="$1"
    
    local engine="${C[engine]}"
    local instance="${C[instance]}"
    
    log_debug "Generating environment template for $engine instance: $instance"
    
    echo "# Environment template for $engine instance: $instance"
    echo "# Generated on $(date)"
    echo "# Usage: dblab up $engine --instance $instance --env-file ${instance}.env"
    echo ""
    
    echo "# ==============================="
    echo "# CONFIGURABLE ENGINE PARAMETERS"
    echo "# ==============================="
    echo ""
    
    # Generate optional env vars from META_ENV_VARS (all non-required variables)
    local count=0
    for key in "${!META_ENV_VARS[@]}"; do
        [[ "$key" =~ ^env_vars\[[0-9]+\]\.name$ ]] && count=$((count + 1))
    done
    
    for ((i = 0; i < count; i++)); do
        local name_key="env_vars[$i].name"
        local required_key="env_vars[$i].required"
        local desc_key="env_vars[$i].description"
        local map_key="env_vars[$i].map"
        
        local env_var="${META_ENV_VARS[$name_key]}"
        local is_required="${META_ENV_VARS[$required_key]:-false}"
        local description="${META_ENV_VARS[$desc_key]:-}"
        local cfg_key="${META_ENV_VARS[$map_key]:-}"
        
        # Get default value from CFG if available
        local default_value=""
        if [[ -n "$cfg_key" && -n "${C[$cfg_key]+_}" ]]; then
            default_value="${C[$cfg_key]}"
        fi
        
        # Generate comment if description exists
        if [[ -n "$description" ]]; then
            echo "# $description"
        fi
        
        if [[ -n "$default_value" ]]; then
            echo "${env_var}=${default_value}"
        elif [[ "$is_required" == "true" ]]; then
            echo "${env_var}=# REQUIRED: Set this value"
        else
            echo "${env_var}="
        fi
        echo ""
    done
    
    echo "# ==============================="
    echo "# INSTANCE METADATA (READ-ONLY)"
    echo "# ==============================="
    echo "# These values will be saved to instance.yml after creation"
    echo "# and cannot be changed via env file after instance creation"
    echo ""
    echo "# DBLAB_INSTANCE=${instance}"
    echo "# DBLAB_ENGINE=${engine}"
    echo "# DBLAB_CREATED=$(date -I)"
    echo ""
    echo "# Network configuration"
    echo "# DBLAB_NETWORK_MODE=${C[network.mode]:-isolated}  # isolated or engine-shared"
    echo ""
    echo "# Data persistence"
    echo "# DBLAB_EPHEMERAL=${C[storage.persistent]:-false}  # true for temporary data"
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
    
    log_debug "Validating environment file: $env_file"
    
    # Use global META_REQUIRED_ENV array from metadata_loader
    local missing_vars=()
    
    for env_var in "${META_REQUIRED_ENV[@]}"; do
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
    done
    
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
