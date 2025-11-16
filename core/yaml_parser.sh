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
        gsub(/^["\047]+|["\047]+$/, "")  # Remove leading/trailing quotes
        print $0
        next
    }
    
    # End of section (next top-level key)
    in_section && /^[[:alpha:]]/ {
        in_section = 0
    }
    ' "$file"
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
