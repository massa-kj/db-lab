#!/bin/bash

# core/env_loader.sh - Environment variable loading with priority layers
# This module handles the 5-layer config priority system described in SPEC.md

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"

# **duplicate**
# Temporary storage for resolved environment
declare -A RESOLVED_ENV=()
# Get resolved environment value
get_env() {
    local key="$1"
    local default="${2:-}"
    
    echo "${RESOLVED_ENV[$key]:-$default}"
}
export -f get_env

# =============================================================
# env_loader.sh
# -------------------------------------------------------------
# Purpose:
#   - Load env-file (multiple files allowed, last wins)
#   - Load OS environment variables DBLAB_* and override
#   - Apply based on metadata.defaults
#   - Static check of required keys based on metadata.required_env
#   - Output env_runtime as assoc-array for later merge_layers
#
# Constraints:
#   - Does not depend on instance.yml structure
#   - Contains no engine-specific logic (doesn't know key meanings)
#
# Expected pre-state:
#   - metadata_loader.sh has already loaded:
#       * META            (assoc)        ... entire engine metadata
#       * META_DEFAULTS   (assoc)        ... defaults section
#       * META_REQUIRED_ENV (assoc-list) ... required_env list
#
# Dependencies:
#   - lib.sh          : log_debug/log_info/log_error/log_fatal
#   - yaml_parser.sh  : none (env internally doesn't handle YAML)
#
# Environment variables:
#   - ENV_FILES : array of env-file paths (set by arg_parser)
#
# Public functions:
#   - env_load <engine> <meta_assoc> <instance_fixed_assoc> <out_env_assoc>
# =============================================================

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"


# -------------------------------------------------------------
# env_load <engine> <meta_assoc> <instance_fixed_assoc> <out_env_assoc>
# -------------------------------------------------------------
env_load() {
    local engine="$1"
    local -n env_files="$2"
    local -n env_map_ref="$3"
    local -n OUT_ENV="$4"       # Output: env-runtime assoc

    log_debug "[env] load for engine=$engine"

    # Temporary map: merge defaults + env-file + OS env
    declare -A env_raw=()

    # 1. Apply env-file group (multiple allowed, last wins)
    # _env_apply_env_files merged
    # 1. Read ENV files (in order of priority from lowest to highest)
    _env_apply_env_files env_files env_raw
    # local f
    # for f in "${env_files[@]}"; do
    #     _load_from_file "$f" env_raw
    # done

    # 2. Apply OS environment variables DBLAB_* (highest priority)
    _env_apply_os_env env_raw

    # 3. Normalize to internal keys
    _normalize env_raw env_map_ref OUT_ENV

    # 3. Static check of required_env
    # _env_check_required merged

    log_debug "[env] merged keys: ${!OUT_ENV[*]}"
}

# ---------------------------------------------------------
# env_loader.load_from_file
#   Load key=value from .env file
#
# @param file_path
# @param assoc_name → Store in env_raw[...] (assumes DBLAB_ prefix)
# ---------------------------------------------------------
_load_from_file() {
    local file="$1"
    local -n out="$2"

    if [[ ! -f "$file" ]]; then
        echo "[env_loader] WARNING: env-file not found: $file" >&2
        return 0
    fi

    while IFS='=' read -r key val; do
        # Skip empty lines and comments
        [[ -z "$key" ]] && continue
        [[ "$key" =~ ^# ]] && continue

        out["$key"]="$val"
    done < "$file"
}

# ---------------------------------------------------------
# env_loader.load_runtime_env
#   Extract DBLAB_* from host environment variables
#
# @param assoc_name → Store in env_raw[...]
# ---------------------------------------------------------
_load_runtime_env() {
    local -n out="$1"

    local key
    for key in $(env | cut -d= -f1); do
        if [[ "$key" == DBLAB_* ]]; then
            out["$key"]="${!key}"
        fi
    done
}

# ---------------------------------------------------------
# env_loader.normalize
#   Convert env_raw[...] (DBLAB_* format) to internal-key format according to env_map[...]
#
# @param env_raw_name
# @param env_map_name
# @param out_assoc_name → Result converted to internal keys
# ---------------------------------------------------------
_normalize() {
    local -n raw="$1"
    local -n env_map="$2"
    local -n out="$3"

    # Count the number of env_vars elements
    count=0
    for key in "${!META_ENV_VARS[@]}"; do
        [[ "$key" =~ ^env_vars\[[0-9]+\]\.name$ ]] && count=$((count + 1))
    done

    local key
    for key in "${!raw[@]}"; do
        # Map to internal key using META_ENV_VARS
        for ((i=0; i<count; i++)); do
            if ([[ "$key" == "${META_ENV_VARS[env_vars[$i].name]}" ]]); then
                local internal="${META_ENV_VARS[env_vars[$i].map]}"
                out["$internal"]="${raw[$key]}"
            fi
        done
    done
}

# =============================================================
# 2) Apply env-file group (last wins)
#   - Assumes ENV_FILES array is defined by arg_parser
#   - Supports only KEY=VALUE format (simple)
# =============================================================
_env_apply_env_files() {
    local -n env_files_ref="$1"
    local -n OUT="$2"

    # If ENV_FILES is undefined, do nothing
    if [[ "${env_files+x}" != "x" ]]; then
        return
    fi

    local file
    for file in "${env_files_ref[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_fatal "[env] env-file not found: $file"
        fi

        log_debug "[env] applying env-file: $file"

        # Read line by line
        local line key value
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip comments and empty lines
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^[[:space:]]*# ]] && continue

            # Support only KEY=VALUE format (split = only once)
            if [[ "$line" != *"="* ]]; then
                continue
            fi

            key="${line%%=*}"
            value="${line#*=}"

            # Remove leading/trailing whitespace
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"

            # Only target DBLAB_*
            if [[ "$key" != DBLAB_* ]]; then
                continue
            fi

            OUT["$key"]="$value"
        done <"$file"
    done
}


# =============================================================
# 3) Apply OS environment variables DBLAB_* (highest priority)
# =============================================================
_env_apply_os_env() {
    local -n OUT="$1"

    local name value
    # Enumerate with env and pick only DBLAB_*
    while IFS='=' read -r name value; do
        [[ "$name" != DBLAB_* ]] && continue
        OUT["$name"]="$value"
    done < <(env)

    log_debug "[env] applied OS DBLAB_* env"
}


# =============================================================
# 4) required_env check
#   - If keys specified in metadata.required_env are not found
#     in any of "defaults + env-file + OS env", error
# =============================================================
_env_check_required() {
    local -n MERGED="$1"

    # META_REQUIRED_ENV is expected to be loaded by metadata_loader.sh
    if ! declare -p META_REQUIRED_ENV &>/dev/null; then
        log_debug "[env] META_REQUIRED_ENV not defined (no required_env)"
        return
    fi

    local missing=()
    local idx key val def

    for idx in "${!META_REQUIRED_ENV[@]}"; do
        key="${META_REQUIRED_ENV[$idx]}"    # Value as list

        val="${MERGED[$key]-}"
        def="${META_DEFAULTS[$key]-}"

        # OK if there's a value in defaults or merged
        if [[ -z "${val}" && -z "${def}" ]]; then
            missing+=("$key")
        fi
    done

    if ((${#missing[@]} > 0)); then
        log_error "[env] missing required env(s): ${missing[*]}"
        log_error "       please set them via env-file or OS DBLAB_*"
        exit 1
    fi
}
