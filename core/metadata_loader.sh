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
    # 1. Parse entire YAML and expand into OUT_META
    # ---------------------------------------------------------
    # yaml_get_map "$metadata_path" OUT_META
    yaml_parse_file "$metadata_path" OUT_META

    # Required key validation
    _metadata_assert_key OUT_META "engine"
    _metadata_assert_key OUT_META "required_env"
    _metadata_assert_key OUT_META "defaults"

    # Engine name consistency check
    if [[ "${OUT_META[engine]}" != "$engine" ]]; then
        log_error "metadata.yml engine mismatch: expected '$engine', got '${OUT_META[engine]}'"
    fi

    # ---------------------------------------------------------
    # 2. Extract defaults section
    # ---------------------------------------------------------
    # if yaml_get_map "$metadata_path" OUT_DEFAULTS "defaults"; then
    if yaml_get_object OUT_META "defaults" OUT_DEFAULTS; then
        :
    else
        log_error "metadata.yml missing defaults section"
    fi

    # ---------------------------------------------------------
    # 3. Get required_env (list)
    # ---------------------------------------------------------
    # declare -gA META_REQUIRED_ENV=()
    # yaml_get_list "$metadata_path" META_REQUIRED_ENV "required_env"
    declare -ga META_REQUIRED_ENV=()
    yaml_get_array OUT_META "required_env" META_REQUIRED_ENV

    if ((${#META_REQUIRED_ENV[@]} == 0)); then
        log_error "metadata.yml: required_env must not be empty"
    fi

    # ---------------------------------------------------------
    # 4. Load version.supported (optional)
    # ---------------------------------------------------------
    # declare -gA META_SUPPORTED_VERSIONS=()
    # yaml_get_list "$metadata_path" META_SUPPORTED_VERSIONS "version.supported" || true
    declare -ga META_SUPPORTED_VERSIONS=()
    yaml_get_array OUT_META "version.supported" META_SUPPORTED_VERSIONS || true

    # Validation for version section
    if yaml_key_exists OUT_META "version"; then
        _metadata_assert_key OUT_META "version.supported";
        _metadata_assert_key OUT_META "version.default";
    fi

    # ---------------------------------------------------------
    # 5. Load generate_template (for env-template)
    # ---------------------------------------------------------
    # declare -gA META_TEMPLATE_ORDER=()
    declare -ga META_TEMPLATE_ORDER=()
    declare -gA META_TEMPLATE_COMMENTS=()

    # yaml_get_list "$metadata_path" META_TEMPLATE_ORDER "generate_template.order" || true
    # yaml_get_map  "$metadata_path" META_TEMPLATE_COMMENTS "generate_template.comments" || true
    yaml_get_array OUT_META "generate_template.order" META_TEMPLATE_ORDER || true
    yaml_get_object OUT_META "generate_template.comments" META_TEMPLATE_COMMENTS || true

    # Validation for cli.args array
    if yaml_key_exists OUT_META "cli"; then
        if yaml_key_exists OUT_META "cli.args"; then
            _metadata_assert_key OUT_META "cli.args[0]";
        fi
    else
        log_debug "No CLI configuration found in metadata (optional)"
    fi

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
