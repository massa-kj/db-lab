#!/usr/bin/env bash
set -euo pipefail

# =============================================================
# metadata_loader.sh
# -------------------------------------------------------------
# Purpose:
#   - Load engines/<engine>/metadata.yml using YAML parser
#   - Validate required structure (engine, required_env, defaults, etc.)
#   - Expand metadata into assoc-arrays
#   - Contains no engine-specific logic (SRP)
#
# Input:
#   metadata_load <engine> <out_meta_assoc> <out_defaults_assoc>
#
# Output:
#   out_meta_assoc[]      → key/value pairs from entire metadata.yml
#   out_defaults_assoc[]  → defaults section only
#
# =============================================================

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=./yaml_parser.sh
source "$(dirname "${BASH_SOURCE[0]}")/yaml_parser.sh"

# -------------------------------------------------------------
# metadata_load <engine> <out_meta> <out_defaults>
# -------------------------------------------------------------
metadata_load() {
    local engine="$1"
    local -n OUT_META="$2"       # assoc-array
    local -n OUT_DEFAULTS="$3"   # assoc-array

    local engine_dir="${DBLAB_ROOT:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/engines/$engine"
    local metadata_path="$engine_dir/metadata.yml"

    if [[ ! -f "$metadata_path" ]]; then
        log_error "metadata.yml not found for engine '$engine': $metadata_path"
    fi

    log_debug "[metadata] loading: $metadata_path"

    # ---------------------------------------------------------
    # Parse entire YAML and expand into OUT_META
    # ---------------------------------------------------------
    yaml_parse_file "$metadata_path" OUT_META

    # Required key validation
    _metadata_assert_key OUT_META "engine"
    _metadata_assert_key OUT_META "env_vars"
    _metadata_assert_key OUT_META "defaults"
    _metadata_assert_key OUT_META "instance_fields"

    # Engine name consistency check
    if [[ "${OUT_META[engine]}" != "$engine" ]]; then
        log_error "metadata.yml engine mismatch: expected '$engine', got '${OUT_META[engine]}'"
    fi

    # ---------------------------------------------------------
    # Extract defaults section
    # ---------------------------------------------------------
    for key in "${!OUT_META[@]}"; do
        if [[ "$key" == defaults.* ]]; then
            local meta_def_key="${key#defaults.}"
            OUT_DEFAULTS["$meta_def_key"]="${OUT_META[$key]}"
        fi
    done

    # ---------------------------------------------------------
    # Load env_vars array (for env-template generation)
    # ---------------------------------------------------------
    declare -gA META_ENV_VARS=()

    # Extract all env_vars[*] keys directly from OUT_META
    for key in "${!OUT_META[@]}"; do
        if [[ "$key" == env_vars\[*\]* ]]; then
            # Copy env_vars keys directly to META_ENV_VARS
            META_ENV_VARS["$key"]="${OUT_META[$key]}"
        fi
    done

    # ---------------------------------------------------------
    # Get required_env (list)
    # ---------------------------------------------------------
    declare -ga META_REQUIRED_ENV=()

    # Count the number of env_vars elements
    count=0
    for key in "${!META_ENV_VARS[@]}"; do
        [[ "$key" =~ ^env_vars\[[0-9]+\]\.name$ ]] && count=$((count + 1))
    done

    # Add only if env_vars[$i].required exists and is true
    for ((i=0; i<count; i++)); do
        local required_key="env_vars[$i].required"
        if [[ "${META_ENV_VARS[$required_key]:-}" == "true" ]]; then
            local name_key="env_vars[$i].name"
            META_REQUIRED_ENV+=("${META_ENV_VARS[$name_key]}")
        fi
    done

    # ---------------------------------------------------------
    # 4. Load version.supported (optional)
    # ---------------------------------------------------------
    declare -ga META_SUPPORTED_VERSIONS=()
    yaml_get_array OUT_META "supported" META_SUPPORTED_VERSIONS || true

    # ---------------------------------------------------------
    #
    # ---------------------------------------------------------
    # Validation for cli.args array
    if yaml_key_exists OUT_META "cli"; then
        if yaml_key_exists OUT_META "cli.args"; then
            _metadata_assert_key OUT_META "cli.args[0]";
        fi
    else
        log_debug "No CLI configuration found in metadata (optional)"
    fi

    # ---------------------------------------------------------
    # 5. Load instance_fields.fixed array
    # ---------------------------------------------------------
    declare -ga META_FIXED=()
    yaml_get_array OUT_META "instance_fields.fixed" META_FIXED || true

    log_debug "[metadata] loaded: engine=$engine required_env=${#META_REQUIRED_ENV[@]} defaults=${#OUT_DEFAULTS[@]}"
}


# =============================================================
# Internal utilities
# =============================================================

# -------------------------------------------------------------
# _metadata_assert_key <assoc> <key>
# -------------------------------------------------------------
_metadata_assert_key() {
    local -n __map="$1"
    local key="$2"

    if ! yaml_key_exists __map "$key"; then
        log_error "metadata.yml missing required key: $key"
    fi
}

client_metadata_load() {
    local engine="$1"
    local -n OUT_META="$2"       # assoc-array
    local -n OUT_DEFAULTS="$3"   # assoc-array

    local engine_dir="${DBLAB_ROOT:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/engines/$engine"
    local metadata_path="$engine_dir/client.yml"

    if [[ ! -f "$metadata_path" ]]; then
        log_error "metadata.yml not found for engine '$engine': $metadata_path"
    fi

    log_debug "[metadata] loading: $metadata_path"

    # ---------------------------------------------------------
    # Parse entire YAML and expand into OUT_META
    # ---------------------------------------------------------
    yaml_parse_file "$metadata_path" OUT_META

    # Required key validation
    # _metadata_assert_key OUT_META "engine"
    # _metadata_assert_key OUT_META "env_vars"
    # _metadata_assert_key OUT_META "defaults"

    # Engine name consistency check
    if [[ "${OUT_META[engine]}" != "$engine" ]]; then
        log_error "metadata.yml engine mismatch: expected '$engine', got '${OUT_META[engine]}'"
    fi

    # ---------------------------------------------------------
    # Extract defaults section
    # ---------------------------------------------------------
    for key in "${!OUT_META[@]}"; do
        if [[ "$key" == defaults.* ]]; then
            local meta_def_key="${key#defaults.}"
            OUT_DEFAULTS["$meta_def_key"]="${OUT_META[$key]}"
        fi
    done

    # ---------------------------------------------------------
    # Load env_vars array (for env-template generation)
    # ---------------------------------------------------------
    declare -gA META_ENV_VARS=()

    # Extract all env_vars[*] keys directly from OUT_META
    for key in "${!OUT_META[@]}"; do
        if [[ "$key" == env_vars\[*\]* ]]; then
            # Copy env_vars keys directly to META_ENV_VARS
            META_ENV_VARS["$key"]="${OUT_META[$key]}"
        fi
    done

    # ---------------------------------------------------------
    # Get required_env (list)
    # ---------------------------------------------------------
    declare -ga META_REQUIRED_ENV=()

    # Count the number of env_vars elements
    count=0
    for key in "${!META_ENV_VARS[@]}"; do
        [[ "$key" =~ ^env_vars\[[0-9]+\]\.name$ ]] && count=$((count + 1))
    done

    # Add only if env_vars[$i].required exists and is true
    for ((i=0; i<count; i++)); do
        local required_key="env_vars[$i].required"
        if [[ "${META_ENV_VARS[$required_key]:-}" == "true" ]]; then
            local name_key="env_vars[$i].name"
            META_REQUIRED_ENV+=("${META_ENV_VARS[$name_key]}")
        fi
    done

    log_debug "[metadata] loaded: engine=$engine required_env=${#META_REQUIRED_ENV[@]} defaults=${#OUT_DEFAULTS[@]}"
}
