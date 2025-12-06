#!/usr/bin/env bash
set -euo pipefail

# =============================================================
# merge_layers.sh
# -------------------------------------------------------------
# Pure function to merge dblab configuration value layers with last-wins strategy.
#
# Public functions:
#   merge_layers <out_assoc> \
#       <metadata_defaults_assoc> \
#       <instance_runtime_assoc> \
#       <env_runtime_assoc> \
#       <cli_runtime_assoc> \
#       <instance_fixed_assoc>
#
# Layer order (lower layers have higher priority):
#   1. metadata.defaults
#   2. instance.runtime
#   3. env.runtime
#   4. cli.options
#   5. instance.fixed (absolute priority - strongest)
#
# Dependencies:
#   - lib.sh (log_debug)
#
# =============================================================

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Required field validation
_validate_required() {
    local merged_name="$1"
    local fields_name="$2"

    local -n MERGED="$merged_name"
    local -n FIELDS="$fields_name"

    local key
    for key in "${!FIELDS[@]}"; do
        # Only check *.required
        if [[ "$key" != *.required ]]; then
            continue
        fi

        local required_flag="${FIELDS[$key]}"
        if [[ "$required_flag" != "true" ]]; then
            continue
        fi

        # db.user.required → db.user
        local base_key="${key%.required}"

        # Doesn't exist or empty
        if [[ -z "${MERGED[$base_key]+_}" || -z "${MERGED[$base_key]}" ]]; then
            echo "[merge_layers] ERROR: required field missing: ${base_key}" >&2
            return 1
        fi
    done
}

# -------------------------------------------------------------
# API: merge_layers (pure function / no side effects)
# -------------------------------------------------------------
merge_layers() {
    local out_name="$1"; shift
    local meta_defaults_name="$1"; shift
    local instance_runtime_name="$1"; shift
    local env_runtime_name="$1"; shift
    local cli_runtime_name="$1"; shift
    local instance_fixed_name="$1"; shift
    local instance_fields_name="$1"; shift

    # Reference with nameref
    local -n DEF="$meta_defaults_name"
    local -n ENV="$env_runtime_name"
    local -n CLI="$cli_runtime_name"
    local -n FIXED="$instance_fixed_name"
    local -n FIELDS="$instance_fields_name"
    local -n OUT="$out_name"

    # Initialize OUT
    for k in "${!OUT[@]}"; do unset "OUT[$k]"; done

    log_debug "[merge] start merging layers"

    local has_instance=0
    if [[ "$instance_runtime_name" != "-" && -n "$instance_runtime_name" ]]; then
        local -n INST="$instance_runtime_name"
        has_instance=1
    fi

    # ----------------------------
    # 1. metadata.defaults (weakest)
    # ----------------------------
    for key in "${!DEF[@]}"; do
        OUT["$key"]="${DEF[$key]}"
    done

    # ----------------------------
    # 2. instance.runtime
    # ----------------------------
    for key in "${!INST[@]}"; do
        OUT["$key"]="${INST[$key]}"
    done

    # ----------------------------
    # 3. env.runtime
    # ----------------------------
    for key in "${!ENV[@]}"; do
        OUT["$key"]="${ENV[$key]}"
    done

    # ----------------------------
    # 4. cli.options (highest priority variable layer)
    # ----------------------------
    for key in "${!CLI[@]}"; do
        OUT["$key"]="${CLI[$key]}"
    done

    # ----------------------------
    # 5. instance.fixed (strongest - absolute priority)
    # ----------------------------
    for key in "${!FIXED[@]}"; do
        OUT["$key"]="${FIXED[$key]}"
    done

    # Required field validation
    # TODO: Need mechanism to skip for commands like list that don't specify instance
    # _validate_required "$out_name" "$instance_fields_name"

    log_debug "[merge] done merging layers; keys=${!OUT[*]}"
}

client_merge_layers() {
    local out_name="$1"; shift
    local meta_defaults_name="$1"; shift
    local env_runtime_name="$1"; shift
    local cli_runtime_name="$1"; shift

    # Reference with nameref
    local -n DEF="$meta_defaults_name"
    local -n ENV="$env_runtime_name"
    local -n CLI="$cli_runtime_name"
    local -n OUT="$out_name"

    # Initialize OUT
    for k in "${!OUT[@]}"; do unset "OUT[$k]"; done

    log_debug "[merge] start merging layers"

    # ----------------------------
    # 1. metadata.defaults (weakest)
    # ----------------------------
    for key in "${!DEF[@]}"; do
        OUT["$key"]="${DEF[$key]}"
    done

    # ----------------------------
    # 3. env.runtime
    # ----------------------------
    for key in "${!ENV[@]}"; do
        OUT["$key"]="${ENV[$key]}"
    done

    # ----------------------------
    # 4. cli.options (highest priority variable layer)
    # ----------------------------
    for key in "${!CLI[@]}"; do
        OUT["$key"]="${CLI[$key]}"
    done

    # Required field validation
    # TODO: Need mechanism to skip for commands like list that don't specify instance
    # _validate_required "$out_name" "$instance_fields_name"

    log_debug "[merge] done merging layers; keys=${!OUT[*]}"
}