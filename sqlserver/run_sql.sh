#!/bin/bash

set -ue

source ./util.sh

# Read environment variables from .env file (default: .env, can override with --env <file>)
ENV_FILE=".env"
NEW_ARGS=()
while [ $# -gt 0 ]; do
    if [ "$1" = "--env" ] && [ -n "$2" ]; then
        ENV_FILE="$2"
        shift 2
    else
        NEW_ARGS+=("$1")
        shift
    fi
done
set -- "${NEW_ARGS[@]}"
export $(grep -v '^#' "$ENV_FILE" | xargs)

# Check if at least one SQL file path is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <sql_file_or_dir> [<sql_file_or_dir> ...]"
    exit 1
fi

for SQL_PATH in "$@"; do
	if [ -f "$SQL_PATH" ]; then
		sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -d "$MY_SQLSERVER_INIT_DATABASE" -i "$SQL_PATH"
		continue
	fi
	# Execute SQL files recursively, directory-first, sorted by name
	extract_sql_files "$SQL_PATH" MY_SQLSERVER_INIT_EXCLUDE_DIRS[@] MY_SQLSERVER_INIT_EXCLUDE_FILES[@] | while read -r sql_file; do
		sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -d "$MY_SQLSERVER_INIT_DATABASE" -i "$sql_file"
		echo "Executed: $sql_file"
	done
done

