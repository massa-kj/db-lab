#!/bin/bash

# core/runner.sh - Container runtime abstraction layer
# Provides unified interface for podman/docker operations

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/detect_engine.sh"

# Container operation state
declare -a RUN_ARGS=()
declare -a EXEC_ARGS=()

# Initialize runtime (called once)
init_runner() {
    # Skip if already initialized
    if [[ -n "${DBLAB_CONTAINER_RUNTIME:-}" ]]; then
        return 0
    fi
    
    init_container_runtime >/dev/null
}

# Reset command arguments
reset_args() {
    RUN_ARGS=()
    EXEC_ARGS=()
}

# Add common run arguments
add_run_arg() {
    RUN_ARGS+=("$@")
}

# Add exec arguments
add_exec_arg() {
    EXEC_ARGS+=("$@")
}

# Set container name
set_container_name() {
    local name="$1"
    add_run_arg "--name" "$name"
}

# Set container image
set_image() {
    local image="$1"
    RUN_ARGS+=("$image")
}

# Add environment variable
add_env() {
    local key="$1"
    local value="$2"
    add_run_arg "-e" "${key}=${value}"
}

# Add port mapping
add_port() {
    local port_mapping="$1"
    add_run_arg "-p" "$port_mapping"
}

# Add volume mount
add_volume() {
    local volume_spec="$1"
    
    # Add :Z for SELinux compatibility if needed
    local runtime="${DBLAB_CONTAINER_RUNTIME:-podman}"
    if [[ "$runtime" == "podman" && "$(get_runtime_capability rootless)" == "true" ]]; then
        # Check if volume_spec already has SELinux flags
        if [[ ! "$volume_spec" =~ :z$ && ! "$volume_spec" =~ :Z$ ]]; then
            volume_spec="${volume_spec}:Z"
        fi
    fi
    
    add_run_arg "-v" "$volume_spec"
}

# Add network
add_network() {
    local network="$1"
    add_run_arg "--network" "$network"
}

# Set detached mode
set_detached() {
    add_run_arg "-d"
}

# Set interactive mode
set_interactive() {
    add_run_arg "-it"
}

# Set remove on exit
set_remove() {
    add_run_arg "--rm"
}

# Add custom argument
add_custom_arg() {
    add_run_arg "$@"
}

# Build and execute run command
run_container() {
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    if [[ ${#RUN_ARGS[@]} -eq 0 ]]; then
        die "No container arguments specified"
    fi
    
    local cmd=("$runtime" "run" "${RUN_ARGS[@]}")
    
    # Execute the command
    "${cmd[@]}"
}

# Execute command in running container
exec_container() {
    local container="$1"
    shift
    local exec_cmd=("$@")
    
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    local cmd=("$runtime" "exec" "${EXEC_ARGS[@]}" "$container" "${exec_cmd[@]}")
    
    # Execute the command
    "${cmd[@]}"
}

# Stop container
stop_container() {
    local container="$1"
    local timeout="${2:-10}"
    
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    if container_exists "$container"; then
        "$runtime" stop -t "$timeout" "$container" || {
            log_warn "Failed to stop container gracefully, forcing stop"
            "$runtime" kill "$container" 2>/dev/null || true
        }
    fi
}

# Remove container
remove_container() {
    local container="$1"
    local force="${2:-false}"
    
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    if container_exists "$container"; then
        local args=()
        if [[ "$force" == "true" ]]; then
            args+=("-f")
        fi
        
        "$runtime" rm "${args[@]}" "$container" || {
            log_warn "Failed to remove container: $container"
            return 1
        }
    fi
}

# Check if container exists
container_exists() {
    local container="$1"
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    "$runtime" ps -a --format "{{.Names}}" | grep -q "^${container}$"
}

# Check if container is running
container_running() {
    local container="$1"
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    
    if [[ -z "$runtime" ]]; then
        return 1
    fi
    
    "$runtime" ps --format "{{.Names}}" | grep -q "^${container}$"
}

# Get container status
get_container_status() {
    local container="$1"
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    if ! container_exists "$container"; then
        echo "not-found"
        return 0
    fi
    
    local status
    status=$("$runtime" ps -a --filter "name=^${container}$" --format "{{.Status}}" | head -1)
    
    case "$status" in
        *"Up "*) echo "running" ;;
        *"Exited "*) echo "stopped" ;;
        *"Created"*) echo "created" ;;
        *) echo "unknown" ;;
    esac
}

# Get container logs
get_container_logs() {
    local container="$1"
    local tail="${2:-100}"
    local follow="${3:-false}"
    
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    local args=()
    
    if [[ "$tail" != "all" ]]; then
        args+=("--tail" "$tail")
    fi
    
    if [[ "$follow" == "true" ]]; then
        args+=("-f")
    fi
    
    "$runtime" logs "${args[@]}" "$container"
}

# Create network
create_network() {
    local network_name="$1"
    local driver="${2:-bridge}"
    
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    if network_exists "$network_name"; then
        return 0
    fi
    
    "$runtime" network create --driver "$driver" "$network_name" || {
        die "Failed to create network: $network_name"
    }
}

# Remove network
remove_network() {
    local network_name="$1"
    local force="${2:-false}"
    
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    if ! network_exists "$network_name"; then
        return 0
    fi
    
    local args=()
    if [[ "$force" == "true" ]]; then
        args+=("-f")
    fi
    
    "$runtime" network rm "${args[@]}" "$network_name" || {
        log_warn "Failed to remove network: $network_name"
        return 1
    }
}

# Check if network exists
network_exists() {
    local network_name="$1"
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    "$runtime" network ls --format "{{.Name}}" | grep -q "^${network_name}$"
}

# List networks
list_networks() {
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    "$runtime" network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
}

# List containers
list_containers() {
    local all="${1:-false}"
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    local args=()
    if [[ "$all" == "true" ]]; then
        args+=("-a")
    fi
    
    "$runtime" ps "${args[@]}" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
}

# Pull image if not exists
ensure_image() {
    local image="$1"
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    if "$runtime" image exists "$image" >/dev/null 2>&1; then
        return 0
    fi
    
    log_info "Pulling image: $image"
    "$runtime" pull "$image" || {
        die "Failed to pull image: $image"
    }
    
    log_info "Image pulled successfully: $image"
}

# Health check for container
container_health_check() {
    local container="$1"
    local runtime="${DBLAB_CONTAINER_RUNTIME:-}"
    if [[ -z "$runtime" ]]; then
        die "Container runtime not initialized. Call init_runner first."
    fi
    
    if ! container_running "$container"; then
        echo "container-not-running"
        return 1
    fi
    
    # Check if health check is defined
    local health_status
    health_status=$("$runtime" inspect "$container" --format "{{.State.Health.Status}}" 2>/dev/null || echo "none")
    
    case "$health_status" in
        "healthy") echo "healthy" ;;
        "unhealthy") echo "unhealthy" ;;
        "starting") echo "starting" ;;
        "none"|"") echo "no-healthcheck" ;;
        *) echo "unknown" ;;
    esac
}

# Helper function to build common container run command
build_standard_run() {
    local container_name="$1"
    local image="$2"
    local network="$3"
    
    reset_args
    set_container_name "$container_name"
    set_detached
    add_network "$network"
    set_image "$image"
}

# Export functions for use by other modules
export -f init_runner reset_args add_run_arg add_exec_arg
export -f set_container_name set_image add_env add_port add_volume add_network
export -f set_detached set_interactive set_remove add_custom_arg
export -f run_container exec_container stop_container remove_container
export -f container_exists container_running get_container_status get_container_logs
export -f create_network remove_network network_exists list_networks list_containers
export -f ensure_image container_health_check build_standard_run
