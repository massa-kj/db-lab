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

# Dependencies: bash 4+, simple YAML with 2-space indentation
# Output: Flat keys stored in caller's associative array via nameref
#   Example: version.supported[0] = "16"

yaml_parse_file() {
    local file="$1"
    local -n YAML_REF="$2"

    # Hold results in YAML_REF (nameref to caller's associative array)
    declare -A YAML_INDEX=()  # Next index for each parent key

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

            YAML_REF["$flat_key"]="$value"
            log_debug "Set YAML_REF[$flat_key]=$value"
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
            YAML_REF["${parent_key}[${idx}]"]="$value"
            YAML_INDEX["$parent_key"]=$(( idx + 1 ))
            log_debug "Set YAML_REF[${parent_key}[${idx}]]=$value"

            continue
        fi

        # Lines that don't match any of the above are ignored for current use (extend if needed)
        log_debug "Skipped unrecognized line: $text"
    done < "$file"
    
    log_debug "YAML parsing completed. Found ${#YAML_REF[@]} keys"
}

yaml_get() {
    local -n yaml_ref="$1"
    local key="$2"
    local default="${3:-}"
    if [[ -v "yaml_ref[$key]" ]]; then
        printf '%s' "${yaml_ref[$key]}"
    else
        printf '%s' "$default"
    fi
}

yaml_has() {
    local -n yaml_ref="$1"
    local key="$2"
    [[ -v "yaml_ref[$key]" ]]
}

# Check if a key exists in yaml_ref (supports partial key matching)
# For example, if yaml_ref has "cli.args[2]", then "cli" and "cli.args" are also considered as existing
yaml_key_exists() {
    local -n yaml_ref="$1"
    local key="$2"
    
    # First check exact match
    if [[ -v "yaml_ref[$key]" ]]; then
        return 0
    fi
    
    # Check if any key starts with the given key followed by a dot or bracket
    # This allows "cli" to match "cli.args[2]" and "cli.args" to match "cli.args[2]"
    local search_pattern="${key}[\.\[]"
    
    for existing_key in "${!yaml_ref[@]}"; do
        if [[ "$existing_key" =~ ^${key}[\.\[] ]]; then
            return 0
        fi
    done
    
    return 1
}

yaml_dump() {
    local -n yaml_ref="$1"
    for k in "${!yaml_ref[@]}"; do
        printf '%s=%s\n' "$k" "${yaml_ref[$k]}"
    done
}

# Get array from YAML data as indexed array
# Example: yaml_get_array metadata "version.supported" supported_versions
# Result: supported_versions=("16" "15" "14" "13")
yaml_get_array() {
    local -n source_ref="$1"
    local array_path="$2"
    local -n target_array="$3"
    
    # Clear target array
    target_array=()
    
    local i=0
    while true; do
        local key="${array_path}[$i]"
        if [[ -v "source_ref[$key]" ]]; then
            target_array+=("${source_ref[$key]}")
            i=$((i + 1))
        else
            break
        fi
    done
    
    log_debug "yaml_get_array: Found ${#target_array[@]} items for '$array_path'"
}

# Get object (key-value pairs) from YAML data as associative array
# Example: yaml_get_object metadata "generate_template.comments" comments
# Result: comments["DBLAB_PG_VERSION"]="Image tag (ex: 16, 16-alpine)", etc.
yaml_get_object() {
    local -n source_ref="$1"
    local object_path="$2"
    local -n target_object="$3"
    
    # Clear target object
    target_object=()
    
    local object_prefix="${object_path}."
    local prefix_len=${#object_prefix}
    
    # Iterate through all keys in source_ref
    for key in "${!source_ref[@]}"; do
        # Check if key starts with the object prefix
        if [[ "$key" == "$object_prefix"* ]]; then
            # Remove object prefix to get the new key
            local new_key="${key:$prefix_len}"
            
            # Skip if new_key is empty or contains dots/brackets (nested structures)
            # This ensures we only get direct children of the object
            if [[ -n "$new_key" && "$new_key" != *.* && "$new_key" != *[* ]]; then
                target_object["$new_key"]="${source_ref[$key]}"
                # Debug output only if log_debug function exists
                if declare -F log_debug >/dev/null 2>&1; then
                    log_debug "yaml_get_object: Set target_object[$new_key]=${source_ref[$key]}"
                fi
            fi
        fi
    done
    
    # Debug output only if log_debug function exists
    if declare -F log_debug >/dev/null 2>&1; then
        log_debug "yaml_get_object: Found ${#target_object[@]} keys for '$object_path'"
    fi
}

export -f yaml_parse_file yaml_get yaml_has yaml_key_exists yaml_dump yaml_get_array yaml_get_object