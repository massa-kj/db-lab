usage() {
    cat <<EOF
Usage: db.sh <engine> <command> [args...]

db:         $(find "${ENGINE_ROOT}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tr '\n' ' ' | sed 's/ $//')
command:    up | down | logs | ps | restart | cli | seed | health | conninfo

DB Alias:   $(for key in "${!DB_ALIASES[@]}"; do printf '%s=%s ' "$key" "${DB_ALIASES[$key]}"; done)

Examples:
    db.sh pg up
    db.sh mysql cli
    db.sh redis health
EOF
}

