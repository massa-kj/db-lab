#!/usr/bin/env bash
set -euo pipefail

resolve_engine_command() {
    local engine="$1" cmd="$2"
    local cmd_path="$DBLAB_ROOT/engines/$engine/cmd/$cmd"
    [[ -x "$cmd_path" ]] && { echo "$cmd_path"; return 0; }
    return 1
}

