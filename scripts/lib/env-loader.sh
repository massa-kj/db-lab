set -euo pipefail

# Safely load a single .env file
load_env_file() {
    local f="$1"
    [[ -f "$f" ]] || return 0

    # Allow CRLF, BOM, trailing whitespace, and loosely process dotenv format
    local tmp
    tmp="$(mktemp)"
    # 1) Remove BOM  2) Remove CR  3) Remove comments/empty lines
    sed '1s/^\xEF\xBB\xBF//' "$f" | tr -d '\r' \
        | awk '
            /^[[:space:]]*#/ {next}        # full-line comment
            /^[[:space:]]*$/ {next}        # empty
            {print}
        ' > "$tmp"

    set -a
    # shellcheck disable=SC1090
    . "$tmp"
    set +a
    rm -f "$tmp"
}

# Load files in a directory in name order (assuming *.env)
load_env_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    # Sort to ensure stable order even with many files
    find "$dir" -maxdepth 1 -type f -name '*.env' -print0 \
        | sort -z \
        | while IFS= read -r -d '' f; do load_env_file "$f"; done
}

# load_env_layers loads environment variable files in a layered manner.
# Arguments:
#   $1: engine name (e.g., "mysql", "postgres")
#   $@: additional environment files or directories (passed via --env, order preserved)
#
# The loading order is:
#   1. Common default environment file
#   2. Engine-specific default environment file
#   3. User override files (if present)
#   4. Additional --env files or directories (applied in specified order, later overrides earlier)
#
# Each layer can override variables from previous layers.
load_env_layers() {
    local engine="$1"; shift
    local -a extra_envs=( "$@" )   # --env で渡されたファイル/ディレクトリの配列（順序維持）

    # 1. Common default
    load_env_file   "${DBLAB_ROOT}/env/default.env"

    # 2. Engine-specific default
    load_env_file   "${ENGINE_ROOT}/${engine}/default.env"

    # 2. Engine-specific user override
    load_env_file   "${XDG_CONFIG_HOME:-$HOME/.local}/dblab/common.local.env"
    load_env_file   "${XDG_CONFIG_HOME:-$HOME/.local}/dblab/${engine}.local.env"

    # 4. Additional --env files or directories
    for e in "${extra_envs[@]}"; do
        if [[ -d "$e" ]]; then load_env_dir "$e"; else load_env_file "$e"; fi
    done
}

