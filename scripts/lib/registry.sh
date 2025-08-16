declare -A DB_ALIASES=()      # e.g. "pg"="postgres"

# Registration API
alias_db() {
    local alias="$1" name="$2"
    DB_ALIASES["$alias"]="$name"
}

