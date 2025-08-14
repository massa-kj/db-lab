#!/usr/bin/env bash
set -euo pipefail

resolve_engine_command() {
    local engine="$1" cmd="$2"

    ENGINE_CMD="$DBLAB_ROOT/engines/$engine/cmd/$cmd"
    COMMON_CMD="$DBLAB_ROOT/engines/common/cmd/$cmd"

    if   [[ -x "$ENGINE_CMD" ]]; then echo "$ENGINE_CMD"; return 0;
    elif [[ -x "$COMMON_CMD" ]]; then echo "$COMMON_CMD"; return 0;
    else return 1;
    fi
}

