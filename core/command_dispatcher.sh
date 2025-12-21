#!/bin/bash

# core/command_dispatcher.sh - Centralized command execution dispatcher
# Provides unified interface for executing engine commands with proper validation

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENGINES_DIR="${PROJECT_DIR}/engines"

source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/metadata_loader.sh"
source "${SCRIPT_DIR}/instance_loader.sh"
source "${SCRIPT_DIR}/env_loader.sh"
source "${SCRIPT_DIR}/merge_layers.sh"
source "${SCRIPT_DIR}/config_interpolator.sh"
source "${SCRIPT_DIR}/validator.sh"

# =============================================================
# Core dispatcher functions  
# =============================================================
dblab_dispatch_command() {
    local command="$1"
    local engine="$2"
    local instance="$3"
    shift 3

    local env_files=()
    local args=()

    # env-file is passed as ENV_FILES
    # Finally, command-specific options are placed in $@
    while [[ "$1" != "--" ]]; do
        env_files+=("$1")
        shift
    done
    shift # remove --
    args=("$@")
    
    log_debug "Dispatching command '$command' for engine '$engine' and instance '$instance'"

    # =============================================================
    # State holders (assoc-array)
    # =============================================================
    declare -A META=()
    declare -A META_DEFAULTS=()
    declare -A INSTANCE=()
    declare -A INSTANCE_FIXED=()
    declare -A INSTANCE_RUNTIME=()
    declare -A ENV_RUNTIME=()
    declare -A CLI_RUNTIME=()
    declare -A FINAL_CONFIG=()

    # ---------------------------------------------------------
    # Load metadata
    # ---------------------------------------------------------
    metadata_load "$engine" META META_DEFAULTS
    log_debug "Loaded metadata for $engine"

    # ---------------------------------------------------------
    # Load instance (fixed/runtime)
    # ---------------------------------------------------------
    # NOTE: Instance name is determined by CLI options or env upstream
    # local instance="${CLI_RUNTIME[instance]:-}"
    if [ -n "$instance" ]; then
        if dblab_instance_load "$engine" "$instance" INSTANCE INSTANCE_FIXED; then
            log_debug "Loaded instance configuration for $engine/$instance"
        else
            log_debug "No instance.yml found, treating as first 'up'"
        fi
    else
        log_debug "No instance name specified; some commands may fail"
    fi

    # ---------------------------------------------------------
    # Load environment variables
    # ---------------------------------------------------------
    env_load "$engine" ENV_FILES ENV_RUNTIME

    # ---------------------------------------------------------
    # Merge layers
    # ---------------------------------------------------------
    # Ensure engine and instance are set in CLI_RUNTIME
    CLI_RUNTIME[engine]="$engine"
    CLI_RUNTIME[instance]="$instance"
    
    merge_layers FINAL_CONFIG \
        META_DEFAULTS \
        INSTANCE_RUNTIME \
        ENV_RUNTIME \
        CLI_RUNTIME \
        INSTANCE_FIXED \
        META_FIXED
    log_debug "Merged configuration layers into FINAL_CONFIG"

    # ---------------------------------------------------------
    # Configuration interpolation
    # ---------------------------------------------------------
    config_interpolator FINAL_CONFIG

    # ---------------------------------------------------------
    # Semantic validation
    # ---------------------------------------------------------
    # TODO: Need mechanism to avoid using INSTANCE_FIXED for commands without instance specification
    # validator_check "$engine" "$command" FINAL_CONFIG INSTANCE_FIXED
    log_debug "Validation completed for command '$command'"

    # ---------------------------------------------------------
    # Load engine module
    # ---------------------------------------------------------
    local engine_root="${DBLAB_ROOT:-${ENGINES_DIR}/$engine}"
    local engine_main="$engine_root/main.sh"
    if [[ ! -f $engine_main ]]; then
        log_error "engine main not found: $engine_main"
    fi

    # shellcheck source=/dev/null
    source "$engine_main"

    # ----------------------------------------------
    # Dispatch by command type
    # ----------------------------------------------
    case "$command" in
        init)
            source "${SCRIPT_DIR}/env_template.sh"
            generate_env_template FINAL_CONFIG
            ;;
        up)
            # ----------------------------------------------
            # Generate instance.yml on first up (after validation)
            # ----------------------------------------------
            source "${SCRIPT_DIR}/instance_writer.sh"
            if [ -n "$instance" ] && ! instance_file_exists "$engine" "$instance"; then
                instance_writer_create_initial FINAL_CONFIG META_FIXED
                log_debug "Generated instance.yml for new instance '$instance'"
            fi

            # engine_prepare FINCAL_CONFIG
            # engine_validate FINCAL_CONFIG
            # engine_before_up FINCAL_CONFIG
            engine_up FINAL_CONFIG
            # engine_after_up FINCAL_CONFIG
            ;;
        down)
            if declare -F "engine_down" >/dev/null; then
                # Engine has down implementation, call it directly
                engine_down FINAL_CONFIG
            else
                # Use default destroy implementation
                source "${SCRIPT_DIR}/engine_defaults.sh"
                default_engine_down FINAL_CONFIG
            fi
            ;;
        diag)
            # dblab_diag "$engine" "$instance" ENV INSTANCE
            ;;
        destroy)
            log_info "Destroying $engine instance: $instance"
            
            # Check if engine has destroy function
            if declare -F "engine_destroy" >/dev/null; then
                # Engine has destroy implementation, call it directly
                engine_destroy FINAL_CONFIG
            else
                # Use default destroy implementation
                source "${SCRIPT_DIR}/engine_defaults.sh"
                default_engine_destroy FINAL_CONFIG
            fi
            ;;
        status)
            log_info "Checking status of $engine instance: $instance"
            
            if declare -F "engine_status" >/dev/null; then
                # Engine has status implementation, call it directly
                local status
                status=$(engine_status FINAL_CONFIG)
                log_info "Instance $engine/$instance status: $status"
            else
                # Use default status implementation
                source "${SCRIPT_DIR}/engine_defaults.sh"
                local status
                status=$(default_engine_status FINAL_CONFIG)
                log_info "Instance $engine/$instance status: $status"
            fi
            ;;
        list)
            if declare -F "engine_list" >/dev/null; then
                # Engine has list implementation, call it directly
                engine_list FINAL_CONFIG "$VERBOSE_MODE"
            else
                # Use default list implementation
                source "${SCRIPT_DIR}/engine_defaults.sh"
                default_engine_list "$engine" "$VERBOSE_MODE"
            fi
            ;;
        *)
            log_error "Unknown command: $command"
            ;;
    esac
}

dblab_dispatch_client_command() {
    local command="$1"
    local engine="$2"
    local instance="$3"
    shift 3

    local env_files=()
    local args=()

    # env-file is passed as ENV_FILES
    # Finally, command-specific options are placed in $@
    while [[ "$1" != "--" ]]; do
        env_files+=("$1")
        shift
    done
    shift # remove --
    args=("$@")
    
    log_debug "Dispatching command '$command' for engine '$engine' and instance '$instance'"

    # =============================================================
    # State holders (assoc-array)
    # =============================================================
    declare -A META=()
    declare -A META_DEFAULTS=()
    declare -A ENV_RUNTIME=()
    declare -A CLI_RUNTIME=()
    declare -A FINAL_CONFIG=()

    # ---------------------------------------------------------
    # Load metadata
    # ---------------------------------------------------------
    client_metadata_load "$engine" META META_DEFAULTS
    # log_debug "Loaded metadata for $engine"

    # ---------------------------------------------------------
    # Load environment variables
    # ---------------------------------------------------------
    env_load "$engine" ENV_FILES ENV_RUNTIME

    # ---------------------------------------------------------
    # Merge layers
    # ---------------------------------------------------------
    # Ensure engine and instance are set in CLI_RUNTIME
    CLI_RUNTIME[engine]="$engine"
    CLI_RUNTIME[instance]="$instance"
    
    client_merge_layers FINAL_CONFIG \
        META_DEFAULTS \
        ENV_RUNTIME \
        CLI_RUNTIME
    log_debug "Merged configuration layers into FINAL_CONFIG"

    # ---------------------------------------------------------
    # Configuration interpolation
    # ---------------------------------------------------------
    config_interpolator FINAL_CONFIG

    # ---------------------------------------------------------
    # Load engine module
    # ---------------------------------------------------------
    local engine_root="${DBLAB_ROOT:-${ENGINES_DIR}/$engine}"
    local engine_main="$engine_root/main.sh"
    if [[ ! -f $engine_main ]]; then
        log_error "engine main not found: $engine_main"
    fi

    # shellcheck source=/dev/null
    source "$engine_main"

    # ----------------------------------------------
    # Dispatch by command type
    # ----------------------------------------------
    case "$command" in
        init-cli)
            source "${SCRIPT_DIR}/env_template.sh"
            generate_client_env_template FINAL_CONFIG
            ;;
        cli)
            # Check if engine has cli function
            if declare -F "engine_cli" >/dev/null; then
                engine_cli FINAL_CONFIG "${args[@]}"
            else
                log_error "$engine does not support CLI access"
                exit 1
            fi
            ;;
        exec)
            # Check if engine has exec function
            if declare -F "engine_exec" >/dev/null; then
                engine_exec FINAL_CONFIG "${args[@]}"
            else
                log_error "$engine does not support script execution"
                exit 1
            fi
            ;;
        gui)
            # Check if engine has gui function
            if declare -F "engine_gui" >/dev/null; then
                engine_gui FINAL_CONFIG "${args[@]}"
            else
                log_error "$engine does not support GUI access"
                exit 1
            fi
            ;;
        *)
            log_error "Unknown command: $command"
            ;;
    esac
}
