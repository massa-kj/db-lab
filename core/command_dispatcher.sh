#!/bin/bash

# core/command_dispatcher.sh - Centralized command execution dispatcher
# Provides unified interface for executing engine commands with proper validation

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENGINES_DIR="${PROJECT_DIR}/engines"

source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"
source "${SCRIPT_DIR}/instance_loader.sh"

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

# Execute a command on an engine with proper validation and setup
dispatch_engine_command() {
    local command="$1"
    local engine="$2"
    local instance="$3"
    shift 3
    local additional_args=("$@")
    
    log_debug "Dispatching command: $command for $engine/$instance"
    
    # Get engine script path
    local project_dir="$(dirname "$SCRIPT_DIR")"
    local engines_dir="${project_dir}/engines"
    local engine_script="${engines_dir}/${engine}/main.sh"
    
    # Validate engine script exists
    if [[ ! -f "$engine_script" ]]; then
        die "Engine script not found: $engine_script"
    fi
    
    # Make sure script is executable
    ensure_executable "$engine_script"
    
    # Execute the engine command
    log_debug "Executing: $engine_script $command $instance ${additional_args[*]}"
    "$engine_script" "$command" "$instance" "${additional_args[@]}"
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
    dispatch_engine_command "up" "$engine" "$instance" "${env_files[@]}"
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

# Execute simple engine commands (down, status, destroy)
dispatch_simple_command() {
    local command="$1"
    local engine="$2" 
    local instance="$3"
    
    local action_verb
    case "$command" in
        down) action_verb="Stopping" ;;
        status) action_verb="Checking status of" ;;
        destroy) action_verb="Destroying" ;;
        *) action_verb="Processing" ;;
    esac
    
    log_info "$action_verb $engine instance: $instance"
    
    # Execute the command
    if [[ "$command" == "status" ]]; then
        # For status command, capture and display the output
        local status
        status=$(dispatch_engine_command "$command" "$engine" "$instance")
        log_info "Instance $engine/$instance status: $status"
    else
        dispatch_engine_command "$command" "$engine" "$instance"
    fi
}

# Export functions for use by other modules
export -f dispatch_engine_command dispatch_up_command dispatch_init_command
export -f dispatch_list_command dispatch_simple_command ensure_executable

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

    # ----------------------------------------------
    # Load metadata.yml
    # ----------------------------------------------
    # TODO: metadata_loader.sh
    local METADATA_FILE="$ENGINES_DIR/${engine}/metadata.yml"
    if [ ! -f "$METADATA_FILE" ]; then
        log_error "metadata.yml not found for engine '$engine' at: $METADATA_FILE"
        return 1
    fi

    declare -A META=()
    log_debug "Attempting to parse metadata file: $METADATA_FILE"
    
    yaml_parse_file "$METADATA_FILE"
    # Copy YAML data to META array
    for k in "${!YAML[@]}"; do 
        META["$k"]="${YAML[$k]}"
    done
    unset YAML

    log_debug "Loaded metadata for $engine"

    # ----------------------------------------------
    # Load instance.yml (if exists)
    # ----------------------------------------------
    declare -A INSTANCE=()
    if [ -n "$instance" ]; then
        if dblab_instance_load "$engine" "$instance" INSTANCE; then
            log_debug "Loaded existing instance.yml"
        else
            log_debug "No instance.yml found, treating as first 'up'"
        fi
    else
        log_debug "No instance name specified; some commands may fail"
    fi

    # ----------------------------------------------
    # Merge env-layer (core -> metadata -> env-file -> env -> CLI)
    # ----------------------------------------------
    # In env_loader.sh:
    # - declare -A ENV
    # - Store the final value in ENV[...]
    # - Check required_env
    #
    dblab_env_merge \
        "$engine" \
        "$instance" \
        META \
        INSTANCE \
        "${env_files[@]}"

    # ENV[...] is confirmed here

    # ----------------------------------------------
    # Validate fixed attributes (engine/version/network)
    # ----------------------------------------------
    # dblab_validate_fixed_attributes \
    #     "$engine" \
    #     "$instance" \
    #     INSTANCE \
    #     ENV

    # ----------------------------------------------
    # Prepare network
    # ----------------------------------------------
    # dblab_network_prepare "$engine" "$instance" ENV INSTANCE

    # ----------------------------------------------
    # Generate instance.yml on first up
    # ----------------------------------------------
    # if [ ! -f "$INSTANCE_FILE" ] && [ "$command" = "up" ]; then
    #     dblab_instance_save "$engine" "$instance" ENV
    #     log_debug "Generated instance.yml for new instance '$instance'"
    # fi

    # ----------------------------------------------
    # Load engine module (main.sh)
    # ----------------------------------------------
    # local ENGINE_MAIN="$ENGINES_DIR/$engine/main.sh"
    # if [ ! -f "$ENGINE_MAIN" ]; then
    #     log_error "Engine module not found: $ENGINE_MAIN"
    # fi
    # source "$ENGINE_MAIN"

    # ----------------------------------------------
    # Dispatch by command type
    # ----------------------------------------------
    case "$command" in
        init)
            dispatch_init_command "$engine" "$instance"
            ;;
        up)
            # engine_prepare "$engine" "$instance" ENV INSTANCE
            # engine_validate "$engine" "$instance" ENV INSTANCE
            # engine_before_up "$engine" "$instance" ENV INSTANCE
            # engine_up "$engine" "$instance" ENV INSTANCE
            # engine_after_up "$engine" "$instance" ENV INSTANCE

            # Set expose environment variables if --expose is specified
            if [[ -n "$EXPOSE_PORTS" ]]; then
                export EXPOSE_PORTS
            fi
            
            # Use the centralized dispatcher with environment validation
            dispatch_up_command "$engine" "$instance" "${ENV_FILES[@]}"
            ;;
        down)
            # engine_down "$engine" "$instance" ENV INSTANCE
            dispatch_simple_command "down" "$engine" "$instance"
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
            # dblab_destroy_instance "$engine" "$instance"
            dispatch_simple_command "destroy" "$engine" "$instance"
            ;;
        status)
            dispatch_simple_command "status" "$engine" "$instance"
            ;;
        list)
            # dblab_list_instances "$engine"
            dispatch_list_command "$engine" "$VERBOSE_MODE"
            ;;
        *)
            log_error "Unknown command: $command"
            ;;
    esac
}
