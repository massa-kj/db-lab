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

# Parses only common arguments and options (such as database name and command).
# Engine-specific arguments/options should be handled by each engine's script.
parse_common_args() {
    db="${1:-}"; DBLAB_COMMAND="${2:-}"
    if [[ -z "${db}" || "${db}" == "-h" || "${db}" == "--help" ]]; then
        usage; exit 1
    fi
    if [[ -z "${DBLAB_COMMAND}" ]]; then
        usage; exit 1
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
    parse_common_args "$@"
    shift 2

    if [[ -n "${DB_ALIASES[$db]+_}" ]]; then
        DBLAB_ENGINE="${DB_ALIASES[$db]}"
    else
        DBLAB_ENGINE="$db"
    fi
    export DBLAB_ENGINE

    # Pre-read common flags (such as --ver, --env, etc. are interpreted by the core and passed to the environment)
    DBLAB_ENVFILES=()
    DBLAB_EXTRA_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env) DBLAB_ENVFILES+=("${2:-}"); shift 2 ;;
            *) DBLAB_EXTRA_ARGS+=("$1"); shift ;;
        esac
    done

    # Load environment variables for specific engine
    load_envs_if_exists "${ENGINE_ROOT}/${DBLAB_ENGINE}/default.env"
    # Load environment variables for specific file
    if [[ ${#DBLAB_ENVFILES[@]} -gt 0 ]]; then
        load_envs_if_exists "${DBLAB_ENVFILES[@]}"
    fi

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

