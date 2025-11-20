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

# Dependencies: bash 4+, simple YAML with 2-space indentation
# Output: Flat keys stored in associative array YAML
#   Example: version.supported[0] = "16"

yaml_parse_file() {
    local file="$1"

    # Hold results in global associative arrays
    declare -gA YAML=()
    declare -gA YAML_INDEX=()  # Next index for each parent key

    if [[ ! -f "$file" ]]; then
        log_error "yaml_parse_file: YAML file not found: $file"
        return 1
    fi

    log_debug "Parsing YAML file: $file"

    # Stack to maintain hierarchy
    local -a context_stack=()  # Example: ["version","supported"]

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comment lines and empty lines first (but don't trim too early for indent analysis)
        # Comment-only lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        # Completely empty lines
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Separate leading indent from rest
        # Example: "    - \"16\"" → indent_str="    ", text="- \"16\""
        local indent_str text
        if [[ "$line" =~ ^([[:space:]]*)(.*)$ ]]; then
            indent_str="${BASH_REMATCH[1]}"
            text="${BASH_REMATCH[2]}"
        else
            # Unexpected but handle it
            text="$line"
            indent_str=""
        fi

        # Remove end-of-line comments (# and after) ※Not handling # in values
        text="${text%%#*}"
        # Remove trailing whitespace
        text="${text%"${text##*[![:space:]]}"}"

        # Recheck: skip if becomes comment-only / empty
        [[ "$text" =~ ^[[:space:]]*$ ]] && continue

        # Calculate hierarchy level from indent width (assuming 2 spaces = 1 level)
        local indent_len=${#indent_str}
        local level=$(( indent_len / 2 ))
        if (( level < 0 )); then level=0; fi

        # -------------------------------
        # 1. "key: value" format
        # -------------------------------
        if [[ "$text" =~ ^([A-Za-z0-9_-]+):[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Remove quotes from value
            value="${value%\"}"; value="${value#\"}"
            value="${value%\'}"; value="${value#\'}"

            # Truncate context_stack to current level and set key there
            context_stack=( "${context_stack[@]:0:$level}" )
            context_stack[$level]="$key"

            # Generate flat key: version.default, defaults.DBLAB_PG_USER etc
            local flat_key
            flat_key="$(IFS=.; echo "${context_stack[*]}")"

            YAML["$flat_key"]="$value"
            log_debug "Set YAML[$flat_key]=$value"
            continue
        fi

        # -------------------------------
        # 2. "key:" section start only
        # -------------------------------
        if [[ "$text" =~ ^([A-Za-z0-9_-]+):[[:space:]]*$ ]]; then
            local key="${BASH_REMATCH[1]}"

            context_stack=( "${context_stack[@]:0:$level}" )
            context_stack[$level]="$key"
            # This line has no value itself, so don't write to YAML
            continue
        fi

        # -------------------------------
        # 3. Array element "- value"
        # -------------------------------
        if [[ "$text" =~ ^-[[:space:]]*(.*)$ ]]; then
            local value="${BASH_REMATCH[1]}"

            value="${value%\"}"; value="${value#\"}"
            value="${value%\'}"; value="${value#\'}"

            # Array parent key is one level up
            local parent_level=$(( level - 1 ))
            if (( parent_level < 0 )); then
                parent_level=0
            fi

            local parent_key
            parent_key="$(IFS=.; echo "${context_stack[*]:0:$parent_level+1}")"

            # Get next index from YAML_INDEX (default to 0 if not found)
            local idx="${YAML_INDEX[$parent_key]:-0}"

            # Example: "version.supported[0]" = "16"
            YAML["${parent_key}[${idx}]"]="$value"
            YAML_INDEX["$parent_key"]=$(( idx + 1 ))
            log_debug "Set YAML[${parent_key}[${idx}]]=$value"

            continue
        fi

        # Lines that don't match any of the above are ignored for current use (extend if needed)
        log_debug "Skipped unrecognized line: $text"
    done < "$file"
    
    log_debug "YAML parsing completed. Found ${#YAML[@]} keys"
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