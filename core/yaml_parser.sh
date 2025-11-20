#!/bin/bash

# core/yaml_parser.sh - Lightweight YAML parser for metadata files
# Provides basic YAML parsing without external dependencies

set -euo pipefail

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# Parse YAML array from file
parse_yaml_array() {
    local file="$1"
    local key="$2"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    # Extract array values using awk
    awk -v key="$key" '
    BEGIN { in_array = 0 }
    
    # Start of array
    /^[[:space:]]*'"$key"'[[:space:]]*:/ {
        in_array = 1
        next
    }
    
    # Array items
    in_array && /^[[:space:]]*-[[:space:]]*/ {
        sub(/^[[:space:]]*-[[:space:]]*/, "")
        gsub(/^["\047]|["\047]$/, "")  # Remove quotes
        print $0
        next
    }
    
    # End of array (next top-level key)
    in_array && /^[[:alpha:]]/ {
        in_array = 0
    }
    ' "$file"
}

# Parse YAML section as key=value pairs
parse_yaml_section() {
    local file="$1"
    local section="$2"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    # Extract section key-value pairs
    awk -v section="$section" '
    BEGIN { in_section = 0 }
    
    # Start of section
    /^[[:space:]]*'"$section"'[[:space:]]*:/ {
        in_section = 1
        next
    }
    
    # Key-value pairs in section
    in_section && /^[[:space:]]+[[:alpha:]]/ {
        gsub(/^[[:space:]]+/, "")
        gsub(/[[:space:]]*:[[:space:]]*/, "=")
        print $0
        next
    }
    
    # End of section (next top-level key)
    in_section && /^[[:alpha:]]/ {
        in_section = 0
    }
    ' "$file" | sed 's/^["\047]*//;s/["\047]*$//;s/=["\047]*/=/;s/["\047]*$//'
}

# Get single YAML value
parse_yaml_value() {
    local file="$1"
    local key="$2"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    grep "^${key}:" "$file" | head -1 | sed "s/^${key}:[[:space:]]*//" | sed 's/^["\047]//;s/["\047]$//'
}

# Validate YAML file basic structure
validate_yaml_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    # Basic validation: check for balanced colons and basic structure
    if ! grep -q ":" "$file"; then
        log_error "Invalid YAML: No key-value pairs found in $file"
        return 1
    fi
    
    # Check for required_env array
    if ! grep -q "^required_env:" "$file"; then
        log_warn "Warning: No required_env section found in $file"
    fi
    
    # Check for defaults section
    if ! grep -q "^defaults:" "$file"; then
        log_warn "Warning: No defaults section found in $file"
    fi
    
    return 0
}

# Export functions
export -f parse_yaml_array parse_yaml_section parse_yaml_value validate_yaml_file

# ---------------------------------------------------------
# New yaml_parser.sh
# YAML to flat key=value parser without yq dependency
# ---------------------------------------------------------
# Features:
# - Flattens hierarchy with dots (db.user, network.mode)
# - Arrays in key[0], key[1] format
# - Comment (#) removal
# - Skip empty lines
# - Values treated as strings (YAML types ignored)
# - Utilities for storing in Bash associative arrays
# ---------------------------------------------------------

# Global associative array (caller should declare -gA YAML)
# declare -gA YAML

yaml_parse_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        log_error "YAML file not found: $file"
        return 1
    fi

    local current_section=""
    local current_subsection=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Remove trailing comments
        line="${line%%#*}"
        # Remove trailing whitespace
        line="${line%"${line##*[![:space:]]}"}"
        
        # Top-level keys (no indentation)
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            current_section="$key"
            current_subsection=""
            
            if [[ -n "$value" ]]; then
                # Remove quotes
                value="${value#\"}"
                value="${value%\"}"
                value="${value#\'}"
                value="${value%\'}"
                YAML["$key"]="$value"
            fi
            
        # Second-level keys (2 spaces indentation)
        elif [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            current_subsection="$key"
            
            if [[ -n "$value" ]]; then
                # Remove quotes
                value="${value#\"}"
                value="${value%\"}"
                value="${value#\'}"
                value="${value%\'}"
                YAML["${current_section}.${key}"]="$value"
            fi
            
        # Third-level keys (4 spaces indentation)
        elif [[ "$line" =~ ^[[:space:]]{4}([a-zA-Z0-9_-]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            if [[ -n "$value" ]]; then
                # Remove quotes
                value="${value#\"}"
                value="${value%\"}"
                value="${value#\'}"
                value="${value%\'}"
                if [[ -n "$current_subsection" ]]; then
                    YAML["${current_section}.${current_subsection}.${key}"]="$value"
                else
                    YAML["${current_section}.${key}"]="$value"
                fi
            fi
            
        # Array items (2 or 4 spaces + dash)
        elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.*)$ ]]; then
            local value="${BASH_REMATCH[1]}"
            # Remove quotes
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            
            # Find array index
            local array_key=""
            if [[ -n "$current_subsection" ]]; then
                array_key="${current_section}.${current_subsection}"
            else
                array_key="$current_section"
            fi
            
            local idx=0
            local check_key="${array_key}[$idx]"
            while [[ -n "${YAML[$check_key]:-}" ]]; do
                ((idx++))
                check_key="${array_key}[$idx]"
            done
            
            YAML["${array_key}[$idx]"]="$value"
        fi
        
    done < "$file"
}

yaml_get() {
    local key="$1"
    local default="${2:-}"
    if [[ -v "YAML[$key]" ]]; then
        printf '%s' "${YAML[$key]}"
    else
        printf '%s' "$default"
    fi
}

yaml_has() {
    local key="$1"
    [[ -v "YAML[$key]" ]]
}

yaml_dump() {
    for k in "${!YAML[@]}"; do
        printf '%s=%s\n' "$k" "${YAML[$k]}"
    done
}

export -f yaml_parse_file yaml_get yaml_has yaml_dump