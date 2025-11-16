#!/bin/bash

# core/detect_engine.sh - Container runtime detection and validation
# Detects and validates podman/docker availability

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# Container runtime preferences (order matters)
if [[ -z "${PREFERRED_RUNTIMES:-}" ]]; then
    readonly PREFERRED_RUNTIMES=("podman" "docker")
fi

# Runtime capabilities cache
declare -A RUNTIME_CAPS=()

# Detect available container runtimes
detect_runtimes() {
    local available_runtimes=()
    
    log_debug "Detecting available container runtimes"
    
    for runtime in "${PREFERRED_RUNTIMES[@]}"; do
        if command_exists "$runtime"; then
            available_runtimes+=("$runtime")
            log_trace "Found runtime: $runtime"
        else
            log_trace "Runtime not found: $runtime"
        fi
    done
    
    if [[ ${#available_runtimes[@]} -eq 0 ]]; then
        die "No container runtime found. Please install podman or docker."
    fi
    
    echo "${available_runtimes[@]}"
}

# Get the preferred container runtime
get_container_runtime() {
    local available_runtimes
    available_runtimes=($(detect_runtimes))
    
    # Use explicitly set backend if available
    if [[ -n "${CONTAINER_BACKEND:-}" ]]; then
        for runtime in "${available_runtimes[@]}"; do
            if [[ "$runtime" == "$CONTAINER_BACKEND" ]]; then
                echo "$CONTAINER_BACKEND"
                return 0
            fi
        done
        die "Requested container backend '$CONTAINER_BACKEND' is not available"
    fi
    
    # Use first available runtime (podman preferred)
    echo "${available_runtimes[0]}"
}

# Check if runtime is rootless
is_rootless() {
    local runtime="$1"
    
    case "$runtime" in
        podman)
            # Check if podman is running in rootless mode
            if [[ "$EUID" -ne 0 ]] && podman info --format="{{.Host.Security.Rootless}}" 2>/dev/null | grep -q "true"; then
                return 0
            fi
            return 1
            ;;
        docker)
            # Docker is rootless if running without sudo and docker context is rootless
            if [[ "$EUID" -ne 0 ]] && docker info 2>/dev/null | grep -q "rootless"; then
                return 0
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Get runtime version
get_runtime_version() {
    local runtime="$1"
    
    case "$runtime" in
        podman)
            podman --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
            ;;
        docker)
            docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check runtime capabilities
check_runtime_capabilities() {
    local runtime="$1"
    
    log_debug "Checking capabilities for runtime: $runtime"
    
    # Clear previous capabilities
    RUNTIME_CAPS=()
    
    # Check basic functionality
    if $runtime info >/dev/null 2>&1; then
        RUNTIME_CAPS[basic]="true"
        log_trace "Runtime has basic functionality"
    else
        RUNTIME_CAPS[basic]="false"
        log_warn "Runtime basic functionality check failed"
        return 1
    fi
    
    # Check network support
    if $runtime network ls >/dev/null 2>&1; then
        RUNTIME_CAPS[network]="true"
        log_trace "Runtime supports networking"
    else
        RUNTIME_CAPS[network]="false"
        log_warn "Runtime networking not available"
    fi
    
    # Check volume support
    if $runtime volume ls >/dev/null 2>&1; then
        RUNTIME_CAPS[volume]="true"
        log_trace "Runtime supports volumes"
    else
        RUNTIME_CAPS[volume]="false"
        log_warn "Runtime volume support not available"
    fi
    
    # Check rootless mode
    if is_rootless "$runtime"; then
        RUNTIME_CAPS[rootless]="true"
        log_trace "Runtime is running in rootless mode"
    else
        RUNTIME_CAPS[rootless]="false"
        log_trace "Runtime is running in privileged mode"
    fi
    
    # Store runtime info
    RUNTIME_CAPS[version]=$(get_runtime_version "$runtime")
    RUNTIME_CAPS[name]="$runtime"
    
    log_debug "Runtime capabilities check completed"
    return 0
}

# Get runtime capability
get_runtime_capability() {
    local capability="$1"
    echo "${RUNTIME_CAPS[$capability]:-unknown}"
}

# Validate runtime requirements
validate_runtime_requirements() {
    local runtime="$1"
    local required_capabilities=("basic" "network")
    
    log_debug "Validating runtime requirements for: $runtime"
    
    check_runtime_capabilities "$runtime" || die "Runtime capability check failed"
    
    for cap in "${required_capabilities[@]}"; do
        if [[ "$(get_runtime_capability "$cap")" != "true" ]]; then
            die "Required capability '$cap' not available in runtime '$runtime'"
        fi
    done
    
    log_debug "Runtime requirements validated successfully"
}

# Show runtime information
show_runtime_info() {
    local runtime
    runtime=$(get_container_runtime)
    
    validate_runtime_requirements "$runtime"
    
    log_info "Container Runtime Information:"
    log_info "=============================="
    log_info "Runtime: $(get_runtime_capability name)"
    log_info "Version: $(get_runtime_capability version)"
    log_info "Rootless: $(get_runtime_capability rootless)"
    log_info "Basic: $(get_runtime_capability basic)"
    log_info "Network: $(get_runtime_capability network)"
    log_info "Volume: $(get_runtime_capability volume)"
}

# Initialize container runtime
init_container_runtime() {
    local runtime
    runtime=$(get_container_runtime)
    
    log_debug "Initializing container runtime: $runtime"
    
    validate_runtime_requirements "$runtime"
    
    # Export runtime for use by other modules
    export DBLAB_CONTAINER_RUNTIME="$runtime"
    
    log_debug "Container runtime initialized: $runtime"
    echo "$runtime"
}

# Check if engine directory exists
engine_exists() {
    local engine="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_dir="$(dirname "$script_dir")"
    local engines_dir="${project_dir}/engines"
    
    if [[ ! -d "${engines_dir}/${engine}" ]]; then
        return 1
    fi
    
    # Check for required files
    local required_files=(
        "${engines_dir}/${engine}/metadata.yml"
        "${engines_dir}/${engine}/main.sh"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_warn "Engine $engine missing required file: $file"
            return 1
        fi
    done
    
    return 0
}

# List available engines
list_engines() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_dir="$(dirname "$script_dir")"
    local engines_dir="${project_dir}/engines"
    local available_engines=()
    
    if [[ ! -d "$engines_dir" ]]; then
        log_warn "Engines directory not found: $engines_dir"
        return 0
    fi
    
    for engine_dir in "$engines_dir"/*; do
        if [[ -d "$engine_dir" ]]; then
            local engine_name
            engine_name=$(basename "$engine_dir")
            
            if engine_exists "$engine_name"; then
                available_engines+=("$engine_name")
            else
                log_debug "Skipping incomplete engine: $engine_name"
            fi
        fi
    done
    
    if [[ ${#available_engines[@]} -eq 0 ]]; then
        log_info "No engines available"
        return 0
    fi
    
    log_info "Available engines:"
    for engine in "${available_engines[@]}"; do
        log_info "  - $engine"
    done
}

# Validate engine exists and is usable
validate_engine() {
    local engine="$1"
    
    if ! engine_exists "$engine"; then
        die "Engine '$engine' is not available or incomplete"
    fi
    
    log_debug "Engine validated: $engine"
}

# Export functions for use by other modules
export -f detect_runtimes get_container_runtime check_runtime_capabilities
export -f validate_runtime_requirements show_runtime_info init_container_runtime
export -f engine_exists list_engines validate_engine get_runtime_capability
