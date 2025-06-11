#!/bin/bash

set -ue

show_help() {
	echo "Usage: $0 [--env <file>] [-d <database_name>] <sql_file_or_dir> [<sql_file_or_dir> ...]"
	echo "Options:"
	echo "  --env <file>         Specify the environment file (default: .env)"
	echo "  -d <name>            Specify the database name to use"
	echo "  -h, --help           Show this help message"
}

source ./util.sh

# Read environment variables from .env file (default: .env, can override with --env <file>)
env_file=".env"
new_args=()

while [ $# -gt 0 ]; do
    if [ "$1" = "--env" ] && [ -n "$2" ]; then
        env_file="$2"
        shift 2
	elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
		show_help
		exit 0
    else
        new_args+=("$1")
        shift
    fi
done
set -- "${new_args[@]}"
export $(grep -v '^#' "$env_file" | xargs)

# Check if at least one SQL file path is provided
if [ $# -lt 1 ]; then
	show_help
    exit 0
fi

for SQL_PATH in "$@"; do
	# Execute SQL files recursively, directory-first, sorted by name
	extract_sql_files "$SQL_PATH" MY_SQLSERVER_INIT_EXCLUDE_DIRS[@] MY_SQLSERVER_INIT_EXCLUDE_FILES[@] | while read -r sql_file; do
		sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -d "$MY_SQLSERVER_INIT_DATABASE" -i "$sql_file"
		echo "Executed: $sql_file"
	done
done

