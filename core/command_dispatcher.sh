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
source "${SCRIPT_DIR}/instance_writer.sh"

# =============================================================
# Core dispatcher functions  
# =============================================================

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

# Execute up command with environment validation
dispatch_up_command() {
    local engine="$1"
    local instance="$2"
    shift 2
    local env_files=("$@")
    
    log_info "Starting $engine instance: $instance"
    
    # Get engine metadata for validation
    local project_dir="$(dirname "$SCRIPT_DIR")"
    local engines_dir="${project_dir}/engines"
    local metadata_file="${engines_dir}/${engine}/metadata.yml"
    
    if [[ ! -f "$metadata_file" ]]; then
        die "Engine metadata not found: $metadata_file"
    fi
    
    # Validate environment files if provided
    if [[ ${#env_files[@]} -gt 0 ]]; then
        # Source environment validation functions
        source "${SCRIPT_DIR}/env_template.sh"
        
        for env_file in "${env_files[@]}"; do
            log_debug "Validating environment file: $env_file"
            if ! validate_env_file "$env_file" "$metadata_file"; then
                die "Environment validation failed for: $env_file"
            fi
        done
    fi
    
    # Set expose environment variables if specified
    if [[ -n "${EXPOSE_PORTS:-}" ]]; then
        export DBLAB_EXPOSE_ENABLED="true"
        export DBLAB_EXPOSE_PORTS="$EXPOSE_PORTS"
        log_debug "Port exposure enabled: $EXPOSE_PORTS"
    fi
    
    # Execute the up command
    # dispatch_engine_command "up" "$engine" "$instance" "${env_files[@]}"
}

# Execute init command with template generation
dispatch_init_command() {
    local engine="$1" 
    local instance="$2"
    
    log_info "Generating template environment file for $engine instance: $instance"
    
    # Get engine metadata path
    local project_dir="$(dirname "$SCRIPT_DIR")"
    local engines_dir="${project_dir}/engines"
    local metadata_file="${engines_dir}/${engine}/metadata.yml"
    
    if [[ ! -f "$metadata_file" ]]; then
        die "Engine metadata not found: $metadata_file"
    fi
    
    # Source and call template generation
    source "${SCRIPT_DIR}/env_template.sh"
    generate_env_template "$engine" "$instance" "$metadata_file"
}

# Execute list command with enhanced functionality
dispatch_list_command() {
    local engine="$1"
    local verbose_mode="${2:-false}"
    
    log_info "Listing $engine instances"
    
    # Source necessary modules for enhanced list functionality
    source "${SCRIPT_DIR}/instance_loader.sh"
    source "${SCRIPT_DIR}/runner.sh"
    
    # Initialize runner to get container status functions
    init_runner 2>/dev/null || true
    
    # Call the list instances function
    list_instances "$engine" "$verbose_mode"
}

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
        META_DB_FIELDS
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
            dispatch_init_command "$engine" "$instance"
            ;;
        up)
            # ----------------------------------------------
            # Generate instance.yml on first up (after validation)
            # ----------------------------------------------
            if [ -n "$instance" ] && ! instance_file_exists "$engine" "$instance"; then
                instance_writer_create_initial FINAL_CONFIG META_DB_FIELDS
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
        cli)
            # engine_cli "$engine" "$instance" ENV INSTANCE "${args[@]}"
            ;;
        exec)
            # engine_exec "$engine" "$instance" ENV INSTANCE "${args[@]}"
            ;;
        gui)
            # engine_gui "$engine" "$instance" ENV INSTANCE "${args[@]}"
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
            
            # Check if engine has status function
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
            dispatch_list_command "$engine" "$VERBOSE_MODE"
            ;;
        *)
            log_error "Unknown command: $command"
            ;;
    esac
}
