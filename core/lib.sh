#!/bin/bash

# core/lib.sh - Core utilities for dblab
# This module provides logging, error handling, and path operations
# that are used across all dblab modules.

set -euo pipefail

# Global variables
DBLAB_LOG_LEVEL="${DBLAB_LOG_LEVEL:-info}"
DBLAB_BASE_DIR="${DBLAB_BASE_DIR:-${HOME}/.local/share/dblab}"

# Log levels: error=1, warn=2, info=3, debug=4, trace=5
declare -A LOG_LEVELS=(
    [error]=1
    [warn]=2
    [info]=3
    [debug]=4
    [trace]=5
)

# Colors for terminal output
if [[ -z "${RED:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly YELLOW='\033[1;33m'
    readonly GREEN='\033[0;32m'
    readonly BLUE='\033[0;34m'
    readonly GRAY='\033[0;37m'
    readonly NC='\033[0m' # No Color
fi

# Get current log level as number
get_log_level() {
    echo "${LOG_LEVELS[${DBLAB_LOG_LEVEL}]:-3}"
}

# Check if a log level should be output
should_log() {
    local level="$1"
    local current_level
    current_level=$(get_log_level)
    local target_level="${LOG_LEVELS[$level]:-3}"

    [[ $target_level -le $current_level ]]
}

# Core logging function
log() {
    local level="$1"
    shift

    if ! should_log "$level"; then
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""

    case "$level" in
        error) color="$RED" ;;
        warn)  color="$YELLOW" ;;
        info)  color="$GREEN" ;;
        debug) color="$BLUE" ;;
        trace) color="$GRAY" ;;
    esac

    printf "${color}[%s] %s: %s${NC}\n" "$timestamp" "$level" "$*" >&2
}

# Convenience logging functions
log_error() { log error "$@"; }
log_warn()  { log warn "$@"; }
log_info()  { log info "$@"; }
log_debug() { log debug "$@"; }
log_trace() { log trace "$@"; }

# Error handling with cleanup
die() {
    log_error "$@"
    exit 1
}

# Safe error handling with optional cleanup function
trap_error() {
    local cleanup_func="${1:-}"

    trap_cleanup() {
        local exit_code=$?
        log_error "Unexpected error occurred (exit code: $exit_code)"

        if [[ -n "$cleanup_func" && "$(type -t "$cleanup_func")" == "function" ]]; then
            log_debug "Running cleanup function: $cleanup_func"
            "$cleanup_func" || log_warn "Cleanup function failed"
        fi

        exit $exit_code
    }

    trap trap_cleanup ERR
}

# Path utilities
ensure_dir() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || die "Failed to create directory: $dir"
    fi
}

# Safe path operations
safe_rm() {
    local path="$1"

    # Safety checks
    if [[ -z "$path" || "$path" == "/" || "$path" == "$HOME" ]]; then
        die "Refusing to remove dangerous path: $path"
    fi

    if [[ ! -e "$path" ]]; then
        return 0
    fi

    rm -rf "$path" || die "Failed to remove: $path"
}

# Get dblab data directory for engine/instance
get_data_dir() {
    local engine="$1"
    local instance="$2"

    if [[ -z "$engine" || -z "$instance" ]]; then
        die "Engine and instance are required for data directory"
    fi

    echo "${DBLAB_BASE_DIR}/${engine}/${instance}"
}

# Mask sensitive information in strings
mask_sensitive() {
    local text="$1"
    local patterns=(
        "password=[^&[:space:]]*"
        "://[^:]*:[^@]*@"  # URLs with credentials
        "DBLAB_.*_PASSWORD=[^[:space:]]*"
        "token=[^&[:space:]]*"
    )

    for pattern in "${patterns[@]}"; do
        text=$(echo "$text" | sed -E "s|$pattern|****|g")
    done

    echo "$text"
}

# Validate instance name format
validate_instance_name() {
    local instance="$1"

    if [[ ! "$instance" =~ ^[a-z0-9][a-z0-9_-]{0,30}$ ]]; then
        die "Invalid instance name: $instance. Must match [a-z0-9][a-z0-9_-]{0,30}"
    fi
}

# Validate engine name format
validate_engine_name() {
    local engine="$1"

    if [[ ! "$engine" =~ ^[a-z0-9]+$ ]]; then
        die "Invalid engine name: $engine. Must match [a-z0-9]+"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get absolute path
get_abs_path() {
    local path="$1"

    if [[ "$path" = /* ]]; then
        echo "$path"
    else
        echo "$(pwd)/$path"
    fi
}

# Initialize dblab environment
init_dblab() {
    ensure_dir "$DBLAB_BASE_DIR"
}

# Safely ensure script is executable (ignore permission errors)
ensure_executable() {
    local script_path="$1"
    if [[ -f "$script_path" ]]; then
        if [[ -w "$script_path" ]]; then
            chmod +x "$script_path" 2>/dev/null || log_debug "Cannot change permissions for $script_path (this is normal for system installations)"
        else
            log_debug "Script not writable, assuming correct permissions: $script_path"
        fi
    else
        die "Script not found: $script_path"
    fi
}

# Export functions for sourcing by other modules
export -f log log_error log_warn log_info log_debug log_trace
export -f die trap_error ensure_dir safe_rm get_data_dir
export -f mask_sensitive validate_instance_name validate_engine_name
export -f command_exists get_abs_path init_dblab

show_assoc_array() {
    local dict_name="$1"
    declare -n dict_ref="$dict_name"

    for key in "${!dict_ref[@]}"; do
        echo "$key=${dict_ref[$key]}"
    done
}
