#!/usr/bin/env bash
set -euo pipefail

# Initializes and exports key directory paths used by the DBLab scripts.
# - DBLAB_ROOT: Root directory of the DBLab project.
# - LIBRARY_ROOT: Directory containing shared script libraries.
# - ENGINE_ROOT: Directory containing engines.
init_paths() {
    DBLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    LIBRARY_ROOT="$DBLAB_ROOT/scripts/lib"
    ENGINE_ROOT="$DBLAB_ROOT/engines"
    export DBLAB_ROOT LIBRARY_ROOT ENGINE_ROOT
}

# Loads engine-specific metadata by sourcing each engine.
# This allows engine-specific configurations and variables to be set in the environment.
load_engine_metas() {
    # Load each engine's meta.sh to get engine-specific configurations
    for meta in "${ENGINE_ROOT}"/*/meta.sh; do
        # shellcheck disable=SC1090
        source "$meta"
    done
}

# Checks that both the database name and command are provided.
# Arguments:
#   $1 - Database name (must not be empty or a help flag)
#   $2 - Command (must not be empty)
# Returns:
#   0 if both arguments are valid, 1 otherwise.
validate_common_args() {
    local db="$1" cmd="$2"
    [[ -z "$db" || "$db" == "-h" || "$db" == "--help" ]] && return 1
    [[ -z "$cmd" ]] && return 1
    return 0
}

# Resolves the database engine name for a given database alias.
# Arguments:
#   $1 - Database alias (e.g., "mysql", "postgres")
# Returns:
#   The resolved database engine name.
resolve_engine() {
    local db="$1"
    if [[ -n "${DB_ALIASES[$db]+_}" ]]; then
        echo "${DB_ALIASES[$db]}"
    else
        echo "$db"
    fi
}

# Loads environment variables for a specific database engine and additional environment files if provided.
# First, loads the default environment file for the given engine.
# Then, if any extra environment files are specified, loads them as well.
# Arguments:
#   $1 - Engine name (e.g., "mysql", "postgres")
#   $@ - Additional environment files to load
load_engine_envs() {
    local engine="$1"
    shift 1
    local envfiles=("$@")

    # Load environment variables for specific engine
    load_envs_if_exists "${ENGINE_ROOT}/${engine}/default.env"
    # Load environment variables for specific file
    if [[ ${#envfiles[@]} -gt 0 ]]; then
        load_envs_if_exists "${envfiles[@]}"
    fi
}

main() {
    ######################
    # Common Preparation #
    ######################
    init_paths

    source "$LIBRARY_ROOT/core.sh"
    source "$LIBRARY_ROOT/registry.sh"
    source "$LIBRARY_ROOT/resolver.sh"

    # Load default common environment variables
    load_envs_if_exists "$DBLAB_ROOT/env/default.env" "$DBLAB_ROOT/env/local.env"

    load_engine_metas

    source "$LIBRARY_ROOT/help.sh"
    source "$LIBRARY_ROOT/engine-lib.sh"

    #######################
    # Command Preparation #
    #######################
    local db="${1:-}" cmd="${2:-}"
    if [[ $# -ge 2 ]]; then
        shift 2
    elif [[ $# -eq 1 ]]; then
        shift 1
    fi

    if ! validate_common_args "$db" "$cmd"; then
        usage
        die "Invalid arguments"
    fi

    DBLAB_COMMAND="$cmd"
    DBLAB_ENGINE="$(resolve_engine "$db")"
    export DBLAB_ENGINE

    # Pre-read common flags (such as --env, etc. are interpreted by the core and passed to the environment)
    DBLAB_ENVFILES=()
    DBLAB_EXTRA_ARGS=()

    # Process additional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env) DBLAB_ENVFILES+=("${2:-}"); shift 2 ;;
            *) DBLAB_EXTRA_ARGS+=("$1"); shift ;;
        esac
    done

    load_engine_envs "$DBLAB_ENGINE" "${DBLAB_ENVFILES[@]}"

    # Ensure the runtime network exists
    ensure_network "$DBLAB_NETWORK_NAME"

    # Command resolution (engines/<engine>/cmd/<command>)
    cmd_path="$(resolve_engine_command "$DBLAB_ENGINE" "$DBLAB_COMMAND")" \
        || die "unknown command: $DBLAB_ENGINE $DBLAB_COMMAND"

    # Replace the shell with the engine command
    exec "$cmd_path" "${DBLAB_EXTRA_ARGS[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

