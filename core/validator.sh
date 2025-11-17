#!/bin/bash

# core/validator.sh - Metadata validation and environment validation
# Validates metadata.yml files and environment variables against engine specifications

set -euo pipefail

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"

# Validate metadata.yml file structure and content
validate_metadata_file() {
    local metadata_file="$1"
    local engine_name="$2"
    
    log_debug "Validating metadata file: $metadata_file for engine: $engine_name"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Metadata file not found: $metadata_file"
        return 1
    fi
    
    # Basic YAML structure validation
    if ! validate_yaml_file "$metadata_file"; then
        log_error "Invalid YAML structure in metadata file: $metadata_file"
        return 1
    fi
    
    # Validate required top-level keys
    local required_keys=("engine" "required_env" "defaults")
    for key in "${required_keys[@]}"; do
        if ! grep -q "^${key}:" "$metadata_file"; then
            log_error "Missing required key '$key' in metadata file: $metadata_file"
            return 1
        fi
    done
    
    # Validate engine name matches
    local declared_engine
    declared_engine=$(parse_yaml_value "$metadata_file" "engine")
    if [[ "$declared_engine" != "$engine_name" ]]; then
        log_error "Engine name mismatch: declared '$declared_engine', expected '$engine_name'"
        return 1
    fi
    
    # Validate engine name format
    if ! validate_engine_name "$declared_engine"; then
        return 1
    fi
    
    # Validate required_env array exists and is not empty
    local required_env_count
    required_env_count=$(parse_yaml_array "$metadata_file" "required_env" | wc -l)
    if [[ "$required_env_count" -eq 0 ]]; then
        log_error "Empty required_env array in metadata file: $metadata_file"
        return 1
    fi
    
    # Validate version section if present
    if grep -q "^version:" "$metadata_file"; then
        _validate_version_section "$metadata_file"
    fi
    
    # Validate validation section if present
    if grep -q "^validation:" "$metadata_file"; then
        _validate_validation_section "$metadata_file"
    fi
    
    log_debug "Metadata file validation successful: $metadata_file"
    return 0
}

# Validate version section in metadata.yml
_validate_version_section() {
    local metadata_file="$1"
    
    # Check for default version
    if ! parse_yaml_section "$metadata_file" "version" | grep -q "^default="; then
        log_warn "No default version specified in metadata file: $metadata_file"
    fi
    
    # Check supported versions array if present
    if grep -q "^[[:space:]]*supported:" "$metadata_file"; then
        local supported_count
        supported_count=$(parse_yaml_array "$metadata_file" "supported" | wc -l)
        if [[ "$supported_count" -eq 0 ]]; then
            log_warn "Empty supported versions array in metadata file: $metadata_file"
        fi
    fi
}

# Validate validation section in metadata.yml
_validate_validation_section() {
    local metadata_file="$1"
    
    # Parse validation rules
    local validation_rules
    validation_rules=$(parse_yaml_section "$metadata_file" "validation")
    
    # Validate regex patterns by testing them
    while IFS='=' read -r key value; do
        if [[ "$key" == *"_regex" ]]; then
            # Test if regex is valid by using it in a grep test
            if ! echo "test" | grep -E "$value" >/dev/null 2>&1 && ! echo "test" | grep -v -E "$value" >/dev/null 2>&1; then
                log_error "Invalid regex pattern for $key: $value"
                return 1
            fi
        fi
    done <<< "$validation_rules"
}

# Validate environment variables against metadata requirements
validate_env_against_metadata() {
    local metadata_file="$1"
    local env_prefix="$2"  # e.g., "DBLAB_PG_"
    
    log_debug "Validating environment against metadata: $metadata_file"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Metadata file not found: $metadata_file"
        return 1
    fi
    
    local validation_failed=false
    
    # Check required environment variables
    local required_vars
    required_vars=$(parse_yaml_array "$metadata_file" "required_env")
    
    while IFS= read -r var_name; do
        [[ -z "$var_name" ]] && continue
        
        # Check if variable exists in RESOLVED_ENV array or environment
        local var_value=""
        if [[ -n "${RESOLVED_ENV[$var_name]:-}" ]]; then
            var_value="${RESOLVED_ENV[$var_name]}"
        elif [[ -n "${!var_name:-}" ]]; then
            var_value="${!var_name}"
        fi
        
        if [[ -z "$var_value" ]]; then
            log_error "Required environment variable not set: $var_name"
            validation_failed=true
        fi
    done <<< "$required_vars"
    
    # Apply validation rules if present
    if grep -q "^validation:" "$metadata_file"; then
        if ! _apply_validation_rules "$metadata_file" "$env_prefix"; then
            validation_failed=true
        fi
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        return 1
    fi
    
    log_debug "Environment validation successful against metadata: $metadata_file"
    return 0
}

# Apply specific validation rules from metadata
_apply_validation_rules() {
    local metadata_file="$1"
    local env_prefix="$2"
    
    local validation_rules
    validation_rules=$(parse_yaml_section "$metadata_file" "validation")
    local validation_failed=false
    
    while IFS='=' read -r key value; do
        [[ -z "$key" ]] && continue
        
        # Remove surrounding quotes from value
        value=$(echo "$value" | sed 's/^["'\'']*//;s/["'\'']*$//')
        
        case "$key" in
            "user_regex")
                local user_var="${env_prefix}USER"
                local user_value=""
                if [[ -n "${RESOLVED_ENV[$user_var]:-}" ]]; then
                    user_value="${RESOLVED_ENV[$user_var]}"
                elif [[ -n "${!user_var:-}" ]]; then
                    user_value="${!user_var}"
                fi
                
                if [[ -n "$user_value" ]]; then
                    if ! echo "$user_value" | grep -qE "$value"; then
                        log_error "Invalid user format: $user_value (must match: $value)"
                        validation_failed=true
                    fi
                fi
                ;;
            "dbname_regex")
                local db_var="${env_prefix}DATABASE"
                local db_value=""
                if [[ -n "${RESOLVED_ENV[$db_var]:-}" ]]; then
                    db_value="${RESOLVED_ENV[$db_var]}"
                elif [[ -n "${!db_var:-}" ]]; then
                    db_value="${!db_var}"
                fi
                
                if [[ -n "$db_value" ]]; then
                    if ! echo "$db_value" | grep -qE "$value"; then
                        log_error "Invalid database name format: $db_value (must match: $value)"
                        validation_failed=true
                    fi
                fi
                ;;
            "password_min_length")
                local pass_var="${env_prefix}PASSWORD"
                local pass_value=""
                if [[ -n "${RESOLVED_ENV[$pass_var]:-}" ]]; then
                    pass_value="${RESOLVED_ENV[$pass_var]}"
                elif [[ -n "${!pass_var:-}" ]]; then
                    pass_value="${!pass_var}"
                else
                    # Try alternative password variable names
                    pass_var="${env_prefix}SA_PASSWORD"
                    if [[ -n "${RESOLVED_ENV[$pass_var]:-}" ]]; then
                        pass_value="${RESOLVED_ENV[$pass_var]}"
                    elif [[ -n "${!pass_var:-}" ]]; then
                        pass_value="${!pass_var}"
                    fi
                fi
                
                if [[ -n "$pass_value" ]]; then
                    local pass_length=${#pass_value}
                    if [[ "$pass_length" -lt "$value" ]]; then
                        log_error "Password too short: minimum $value characters required"
                        validation_failed=true
                    fi
                fi
                ;;
        esac
    done <<< "$validation_rules"
    
    [[ "$validation_failed" != "true" ]]
}

# Validate supported version against metadata
validate_version_support() {
    local metadata_file="$1"
    local version="$2"
    
    log_debug "Validating version support: $version against $metadata_file"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Metadata file not found: $metadata_file"
        return 1
    fi
    
    # If no supported versions are specified, allow any version
    if ! grep -q "^[[:space:]]*supported:" "$metadata_file"; then
        log_debug "No version restrictions in metadata, allowing version: $version"
        return 0
    fi
    
    # Check if version is in supported list
    local supported_versions
    supported_versions=$(parse_yaml_array "$metadata_file" "supported")
    
    if echo "$supported_versions" | grep -qx "$version"; then
        log_debug "Version $version is supported"
        return 0
    else
        log_error "Unsupported version: $version. Supported versions: $(echo "$supported_versions" | tr '\n' ' ')"
        return 1
    fi
}

# Get default values from metadata
get_metadata_defaults() {
    local metadata_file="$1"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Metadata file not found: $metadata_file"
        return 1
    fi
    
    # Return defaults section as key=value pairs
    parse_yaml_section "$metadata_file" "defaults"
}

# Get required environment variables from metadata
get_required_env_vars() {
    local metadata_file="$1"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Metadata file not found: $metadata_file"
        return 1
    fi
    
    # Return required_env array as newline-separated list
    parse_yaml_array "$metadata_file" "required_env"
}

# Validate engine directory structure
validate_engine_structure() {
    local engine_dir="$1"
    local engine_name="$2"
    
    log_debug "Validating engine structure: $engine_dir"
    
    if [[ ! -d "$engine_dir" ]]; then
        log_error "Engine directory not found: $engine_dir"
        return 1
    fi
    
    # Check for required files
    local required_files=("metadata.yml" "main.sh")
    for file in "${required_files[@]}"; do
        if [[ ! -f "$engine_dir/$file" ]]; then
            log_error "Required file missing in engine directory: $file"
            return 1
        fi
    done
    
    # Validate metadata file
    if ! validate_metadata_file "$engine_dir/metadata.yml" "$engine_name"; then
        return 1
    fi
    
    # Check for optional files and warn if missing
    local optional_files=("exec.sh" "cli.sh" "gui.sh" "health.sh")
    for file in "${optional_files[@]}"; do
        if [[ ! -f "$engine_dir/$file" ]]; then
            log_debug "Optional file missing in engine directory: $file"
        fi
    done
    
    log_debug "Engine structure validation successful: $engine_dir"
    return 0
}

# Comprehensive validation for engine setup
validate_engine_configuration() {
    local engine_name="$1"
    local engines_dir="${2:-engines}"
    local env_prefix="$3"  # e.g., "DBLAB_PG_"
    
    log_info "Validating engine configuration: $engine_name"
    
    local engine_dir="$engines_dir/$engine_name"
    
    # Validate engine name format
    if ! validate_engine_name "$engine_name"; then
        return 1
    fi
    
    # Validate engine directory structure
    if ! validate_engine_structure "$engine_dir" "$engine_name"; then
        return 1
    fi
    
    # Validate environment against metadata (if env_prefix provided)
    if [[ -n "${env_prefix:-}" ]]; then
        if ! validate_env_against_metadata "$engine_dir/metadata.yml" "$env_prefix"; then
            return 1
        fi
    fi
    
    log_info "Engine configuration validation successful: $engine_name"
    return 0
}

# Export functions for use by other modules
export -f validate_metadata_file validate_env_against_metadata validate_version_support
export -f get_metadata_defaults get_required_env_vars validate_engine_structure
export -f validate_engine_configuration
