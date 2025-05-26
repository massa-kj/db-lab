#!/bin/bash

set -ue

source ./util.sh

# Read environment variables from .env file
export $(grep -v '^#' .env | xargs)

# Check if at least one SQL file path is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <sql_file_or_dir> [<sql_file_or_dir> ...]"
    exit 1
fi

for SQL_PATH in "$@"; do
	if [ -f "$SQL_PATH" ]; then
		sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -d "$MY_SQLSERVER_DATABASE" -i "$SQL_PATH"
		continue
	fi
	# Execute SQL files recursively, directory-first, sorted by name
	extract_sql_files "$SQL_PATH" EXCLUDE_DIRS[@] EXCLUDE_FILES[@] | while read -r sql_file; do
		sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -d "$MY_SQLSERVER_DATABASE" -i "$sql_file"
	done
done

