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


# -------------------------------------------------------------
# API: merge_layers (pure function / no side effects)
# -------------------------------------------------------------
merge_layers() {
    local out_name="$1"; shift
    local -n meta_defaults_ref="$1"; shift
    local -n instance_runtime_ref="$1"; shift
    local -n env_runtime_ref="$1"; shift
    local -n cli_runtime_ref="$1"; shift
    local -n instance_fixed_ref="$1"; shift

    # Output destination assoc-array
    local -n OUT="$out_name"

    # Initialize OUT
    for k in "${!OUT[@]}"; do unset "OUT[$k]"; done

    log_debug "[merge] start merging layers"

    # ----------------------------
    # 1. metadata.defaults (weakest)
    # ----------------------------
    for key in "${!meta_defaults_ref[@]}"; do
        OUT["$key"]="${meta_defaults_ref[$key]}"
    done

    # ----------------------------
    # 2. instance.runtime
    # ----------------------------
    for key in "${!instance_runtime_ref[@]}"; do
        OUT["$key"]="${instance_runtime_ref[$key]}"
    done

    # ----------------------------
    # 3. env.runtime
    # ----------------------------
    for key in "${!env_runtime_ref[@]}"; do
        OUT["$key"]="${env_runtime_ref[$key]}"
    done

    # ----------------------------
    # 4. cli.options (highest priority variable layer)
    # ----------------------------
    for key in "${!cli_runtime_ref[@]}"; do
        OUT["$key"]="${cli_runtime_ref[$key]}"
    done

    # ----------------------------
    # 5. instance.fixed (strongest - absolute priority)
    # ----------------------------
    for key in "${!instance_fixed_ref[@]}"; do
        OUT["$key"]="${instance_fixed_ref[$key]}"
    done

    log_debug "[merge] done merging layers; keys=${!OUT[*]}"
}
