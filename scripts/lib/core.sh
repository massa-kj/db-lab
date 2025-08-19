#!/usr/bin/env bash
set -euo pipefail

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { printf '[%s][ERROR]: %s\n' "$*" >&2; exit 1; }

load_envs_if_exists() {
    for f in "$@"; do
        if [[ -f "$f" ]]; then
            set -a; source "$f"; set +a
        fi
    done
}

