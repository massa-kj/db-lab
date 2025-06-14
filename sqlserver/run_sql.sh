#!/usr/bin/env bash

set -euo pipefail

show_help() {
	echo "Usage: $0 [--env <file>] [-d <database_name>] <sql_file_or_dir> [<sql_file_or_dir> ...]"
	echo "Options:"
	echo "  --env <file>         Specify the environment file (default: .env)"
	echo "  -d <name>            Specify the database name to use"
	echo "  -h, --help           Show this help message"
}

source ./util.sh

db_name=""
new_args=()

# Process command-line arguments
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi
while [ $# -gt 0 ]; do
    if [ "$1" = "--env" ] && [ -n "$2" ]; then
        env_file="$2"
        shift 2
	elif [ "$1" = "-d" ] && [ -n "$2" ]; then
		db_name="$2"
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

# Check if at least one SQL file path is provided
if [ $# -lt 1 ]; then
	show_help
    exit 1
fi

# if not ENV_DISABLE_DOTENV=true, load environment variables from the specified file
load_env_file "${env_file:-.env}"

# Validate required environment variables
REQUIRED_VARS=(
	"MY_SQLSERVER_SERVERNAME"
	"MY_SQLSERVER_SA_USERNAME"
	"MY_SQLSERVER_SA_PASSWORD"
)
validate_env_vars "${REQUIRED_VARS[@]}"

if [[ -n "${MY_SQLSERVER_EXCLUDE_DIRS:-}" ]]; then
    IFS=',' read -ra EXCLUDE_DIRS <<< "$MY_SQLSERVER_EXCLUDE_DIRS"
    echo "Excluding directories: ${EXCLUDE_DIRS[*]}"
else
    EXCLUDE_DIRS=()
fi

if [[ -n "${MY_SQLSERVER_EXCLUDE_FILES:-}" ]]; then
    IFS=',' read -ra EXCLUDE_FILES <<< "$MY_SQLSERVER_EXCLUDE_FILES"
    echo "Excluding files: ${EXCLUDE_FILES[*]}"
else
    EXCLUDE_FILES=()
fi

if ! command -v sqlcmd &> /dev/null; then
    echo "Error: sqlcmd command not found. Please install the SQL Server command-line tools."
    exit 1
fi

# Wait until SQL Server is ready
wait_for_db "sqlcmd -S \"$MY_SQLSERVER_SERVERNAME\" -U \"$MY_SQLSERVER_SA_USERNAME\" -P \"$MY_SQLSERVER_SA_PASSWORD\" -Q \"SELECT 1\" &> /dev/null" || exit 1

for SQL_PATH in "$@"; do
	# Execute SQL files recursively, directory-first, sorted by name
	extract_sql_files "$SQL_PATH" EXCLUDE_DIRS[@] EXCLUDE_FILES[@] | while read -r sql_file; do
		if [ -z "$db_name" ]; then
			# If no database name is specified, use the default database
			if [ -z "${MY_SQLSERVER_DEFAULT_DATABASE:-}" ]; then
				echo "Error: MY_SQLSERVER_DEFAULT_DATABASE is not set." >&2
				exit 1
			fi
			db_name="$MY_SQLSERVER_DEFAULT_DATABASE"
		fi
		sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -d "$db_name" -i "$sql_file"
		# if ! sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -d "$db_name" -i "$sql_file"; then
		# 	echo "Error: Failed to execute $sql_file" >&2
		# 	exit 1
		# fi
		echo "Executed: $sql_file"
	done
done

