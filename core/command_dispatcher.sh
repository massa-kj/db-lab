#!/bin/bash

# core/command_dispatcher.sh - Centralized command execution dispatcher
# Provides unified interface for executing engine commands with proper validation

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

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
