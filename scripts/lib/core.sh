#!/usr/bin/env bash
set -euo pipefail

# registry
declare -A DB_ALIASES=()      # e.g. "pg"="postgres"

# Registration API
alias_db() {
    local alias="$1" name="$2"
    DB_ALIASES["$alias"]="$name"
}

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

load_envs_if_exists() {
    for f in "$@"; do
        if [[ -f "$f" ]]; then
            set -a; source "$f"; set +a
        fi
    done
}

ensure_network() {
    if ! ${DBLAB_RUNTIME} network inspect "${DBLAB_NETWORK_NAME}" >/dev/null 2>&1; then
        ${DBLAB_RUNTIME} network create "${DBLAB_NETWORK_NAME}" >/dev/null
    fi
}

compose() { ${DBLAB_RUNTIME} compose "$@"; }
ctr_exec(){ ${DBLAB_RUNTIME} exec "$@"; }

