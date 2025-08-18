#!/usr/bin/env bash
set -euo pipefail

######################
# Common Preparation #
######################
DBLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBRARY_ROOT="$DBLAB_ROOT/scripts/lib"
ENGINE_ROOT="$DBLAB_ROOT/engines"
export DBLAB_ROOT LIBRARY_ROOT ENGINE_ROOT

source "$LIBRARY_ROOT/core.sh"
source "$LIBRARY_ROOT/registry.sh"
source "$LIBRARY_ROOT/resolver.sh"

# Load default common environment variables
load_envs_if_exists "$DBLAB_ROOT/env/default.env" "$DBLAB_ROOT/env/local.env"

# load each engine meta.sh
for meta in "${ENGINE_ROOT}"/*/meta.sh; do
    # shellcheck disable=SC1090
    source "$meta"
done

source "$LIBRARY_ROOT/help.sh"
source "$LIBRARY_ROOT/engine-lib.sh"

# Ensure the runtime network exists
ensure_network "$DBLAB_NETWORK_NAME"

#######################
# Command Preparation #
#######################
# Parse command line arguments
db="${1:-}"; DBLAB_COMMAND="${2:-}"; shift 2 || true

if [[ -z "$db" || "$db" == "-h" || "$db" == "--help" ]]; then
    usage; exit 1
fi
if [[ -n "${DB_ALIASES[$db]+_}" ]]; then
    DBLAB_ENGINE="${DB_ALIASES[$db]}"
else
    DBLAB_ENGINE="$db"
fi

# Load environment variables for specific engine
load_envs_if_exists "${ENGINE_ROOT}/${DBLAB_ENGINE}/default.env"

if [[ -z "$DBLAB_COMMAND" ]]; then
    usage; exit 1
fi

# Pre-read common flags (such as --ver, --env, etc. are interpreted by the core and passed to the environment)
DBLAB_VER=""
DBLAB_ENVFILES=()
DBLAB_EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ver) DBLAB_VER="$2:-"; shift 2 ;;
        --env) DBLAB_ENVFILES+=("$2:-"); shift 2 ;;
        *) DBLAB_EXTRA_ARGS+=("$1"); shift ;;
    esac
done
export DBLAB_ENGINE DBLAB_VER

# Load environment variables for specific file
if [[ ${#DBLAB_ENVFILES[@]} -gt 0 ]]; then
    load_envs_if_exists "${DBLAB_ENVFILES[@]}"
fi

# Command resolution (engines/<engine>/cmd/<command>)
cmd_path="$(resolve_engine_command "$DBLAB_ENGINE" "$DBLAB_COMMAND")" \
|| die "unknown command: $DBLAB_ENGINE $DBLAB_COMMAND"

# Load the engine's manifest to inject defaults/capabilities
manifest_path="${ENGINE_ROOT}/${DBLAB_ENGINE}/manifest.sh"
[[ -f "$manifest_path" ]] && source "$manifest_path"

# Replace the shell with the engine command
exec "$cmd_path" "${DBLAB_EXTRA_ARGS[@]}"

