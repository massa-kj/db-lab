#!/usr/bin/env bash
set -euo pipefail

DBLAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DBLAB_ROOT

source "$DBLAB_ROOT/scripts/lib/core.sh"
source "$DBLAB_ROOT/scripts/lib/discover.sh"

load_envs_if_exists "$DBLAB_ROOT/env/default.env" "$DBLAB_ROOT/env/local.env"

export DBLAB_RUNTIME="${DBLAB_RUNTIME:-docker}"
export DBLAB_NETWORK_NAME="${DBLAB_NETWORK_NAME:-dblab-net}"

# Ensure the runtime network exists
ensure_network "$DBLAB_NETWORK_NAME"

# Parse command line arguments
if [[ $# -lt 2 ]]; then
    echo "Usage: db <engine> <command> [args...]"
    echo " ex):   db postgres up --ver 16 --with engine,cli"
    exit 1
fi

db="$1"; shift
DBLAB_COMMAND="$1"; shift

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
export DBLAB_ENGINE DBLAB_VER DBLAB_ENVFILES

# Load environment variables (overwrite in the order: default → local → specified)
load_envs_if_exists "${DBLAB_ENVFILES[@]:-}"

# load each engine meta.sh
for meta in "${DBLAB_ROOT}"/engines/*/meta.sh; do
    # shellcheck disable=SC1090
    source "$meta"
done

if [[ -n "$db" && -n "${DB_ALIASES[$db]+_}" ]]; then
    # alias resolution
    db="${DB_ALIASES[$db]}"
fi
DBLAB_ENGINE="${db}"

# Command resolution (engines/<engine>/cmd/<command>)
cmd_path="$(resolve_engine_command "$DBLAB_ENGINE" "$DBLAB_COMMAND")" \
|| die "unknown command: $DBLAB_ENGINE $DBLAB_COMMAND"

# Load the engine's manifest to inject defaults/capabilities
manifest_path="$DBLAB_ROOT/engines/$DBLAB_ENGINE/manifest.sh"
[[ -f "$manifest_path" ]] && source "$manifest_path"

# Execute the command
exec "$cmd_path" "${DBLAB_EXTRA_ARGS[@]}"

