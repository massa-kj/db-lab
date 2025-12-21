#!/bin/bash

# core/instance_loader.sh - Instance metadata management
# Handles instance.yml files for persistent instance configuration

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"
source "${SCRIPT_DIR}/instance_manager.sh"

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

CORE_FIXED_KEYS=(
    engine
    created
)

# =============================================================
# Fixed Attribute Extraction
# =============================================================
_instance_extract_fixed() {
    local -n RAW="$1"
    local -n OUT="$2"

    # Extract fixed attributes of the engine
    for key in "${META_FIXED[@]}"; do
        OUT["$key"]="${RAW[$key]}"
    done

    # Extract core fixed attributes
    for key in "${CORE_FIXED_KEYS[@]}"; do
        OUT["$key"]="${RAW[$key]}"
    done
}
