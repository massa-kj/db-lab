#!/usr/bin/env bash
set -euo pipefail

# engines/sqlite/validator.sh - SQLite-specific validation rules
# This file contains validation logic specific to SQLite engine

# Source required modules
SQLITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SQLITE_DIR}/../../core/lib.sh"

# =============================================================
# SQLite-specific validation rules
# =============================================================

_validate_sqlite_file_path() {
    local engine="$1"
    local verb="$2"
    local -n CFG="$3"
    local -n FIXED="$4"

    # Only apply to SQLite engine
    [[ "$engine" != "sqlite" ]] && return 0

    local file_path="${CFG[db.file_path]:-}"
    local data_dir="${CFG[storage.data_dir]:-}"

    # Check if file path is specified
    if [[ -z "$file_path" ]]; then
        log_error "[validator] SQLite db.file_path is required"
        return 1
    fi

    # Check file extension
    local extension="${CFG[db.file_extension]:-}"
    if [[ -n "$extension" && ! "$file_path" =~ \$extension$ ]]; then
        log_debug "[validator] SQLite file path should end with $extension: $file_path"
    fi

    # For up operations, check if data directory is writable (if it exists)
    if [[ "$verb" == "up" && -n "$data_dir" ]]; then
        # Create parent directory if it doesn't exist for validation
        local parent_dir
        parent_dir=$(dirname "$data_dir")
        if [[ -d "$parent_dir" && ! -w "$parent_dir" ]]; then
            log_error "[validator] SQLite data directory parent is not writable: $parent_dir"
            return 1
        fi
    fi

    return 0
}

_validate_sqlite_journal_mode() {
    local engine="$1"
    local verb="$2"
    local -n CFG="$3"
    local -n FIXED="$4"

    # Only apply to SQLite engine
    [[ "$engine" != "sqlite" ]] && return 0

    local journal_mode="${CFG[sqlite.journal_mode]:-}"

    if [[ -n "$journal_mode" ]]; then
        case "$journal_mode" in
            DELETE|TRUNCATE|PERSIST|MEMORY|WAL|OFF)
                return 0 ;;
            *)
                log_error "[validator] Invalid SQLite journal_mode: $journal_mode (must be DELETE, TRUNCATE, PERSIST, MEMORY, WAL, or OFF)"
                return 1 ;;
        esac
    fi

    return 0
}

_validate_sqlite_foreign_keys() {
    local engine="$1"
    local verb="$2"
    local -n CFG="$3"
    local -n FIXED="$4"

    # Only apply to SQLite engine
    [[ "$engine" != "sqlite" ]] && return 0

    local foreign_keys="${CFG[sqlite.foreign_keys]:-}"

    if [[ -n "$foreign_keys" ]]; then
        case "$foreign_keys" in
            ON|OFF|on|off|1|0)
                return 0 ;;
            *)
                log_error "[validator] Invalid SQLite foreign_keys: $foreign_keys (must be ON, OFF, 1, or 0)"
                return 1 ;;
        esac
    fi

    return 0
}

_validate_sqlite_timeout() {
    local engine="$1"
    local verb="$2"
    local -n CFG="$3"
    local -n FIXED="$4"

    # Only apply to SQLite engine
    [[ "$engine" != "sqlite" ]] && return 0

    local timeout="${CFG[sqlite.timeout]:-}"

    if [[ -n "$timeout" ]]; then
        # Check if timeout is a positive integer
        if [[ ! "$timeout" =~ ^[0-9]+$ ]] || [[ "$timeout" -lt 0 ]]; then
            log_error "[validator] Invalid SQLite timeout: $timeout (must be a non-negative integer)"
            return 1
        fi
    fi

    return 0
}

_validate_sqlite_no_network_exposure() {
    local engine="$1"
    local verb="$2"
    local -n CFG="$3"
    local -n FIXED="$4"

    # Only apply to SQLite engine
    [[ "$engine" != "sqlite" ]] && return 0

    local expose_enabled="${CFG[runtime.expose.enabled]:-false}"

    if [[ "$expose_enabled" == "true" ]]; then
        log_warn "[validator] SQLite doesn't use network ports, ignoring expose settings"
    fi

    return 0
}

# =============================================================
# Register SQLite validation rules
# =============================================================
sqlite_register_validation_rules() {
    # This function will be called by main.sh to register rules
    if declare -f validator_register_rule &>/dev/null; then
        validator_register_rule "_validate_sqlite_file_path"
        validator_register_rule "_validate_sqlite_journal_mode"
        validator_register_rule "_validate_sqlite_foreign_keys"
        validator_register_rule "_validate_sqlite_timeout"
        validator_register_rule "_validate_sqlite_no_network_exposure"
    fi
}
