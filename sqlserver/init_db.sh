#!/bin/bash

set -e

SQL_PATH="./sql/init"
EXCLUDE_DIRS=("exclude_this_dir")
EXCLUDE_FILES=("skip_this.sql")

# Read environment variables from .env file
export $(grep -v '^#' .env | xargs)

# Validate required environment variables
REQUIRED_VARS=("MY_SQLSERVER_SERVERNAME" "MY_SQLSERVER_SA_USERNAME" "MY_SQLSERVER_SA_PASSWORD" "MY_SQLSERVER_DATABASE")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Error: Environment variable $var is not set or is empty."
    exit 1
  fi
done

# Wait until SQL Server is ready
echo "Waiting for SQL Server to start..."
if ! command -v sqlcmd &> /dev/null; then
	echo "Error: sqlcmd command not found. Please install the SQL Server command-line tools."
	exit 1
fi
until sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -Q "SELECT 1" &> /dev/null; do
	sleep 1
done

# Create database if not exists
echo "Creating database ${MY_SQLSERVER_DATABASE} if it does not exist..."
sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -Q "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = N'${MY_SQLSERVER_DATABASE}') CREATE DATABASE [${MY_SQLSERVER_DATABASE}]"

# Function to check if a value is in an array
contains() {
	local e match="$1"
	shift
	for e; do [[ "$e" == "$match" ]] && return 0; done
	return 1
}

# Execute SQL files recursively, directory-first, sorted by name
echo "Running SQL files in $SQL_PATH..."
find "$SQL_PATH" -type d | sort | while read -r dir; do
	dir_name=$(basename "$dir")
	if contains "$dir_name" "${EXCLUDE_DIRS[@]}"; then
		echo "Skipping directory $dir..."
		continue
	fi

	find "$dir" -maxdepth 1 -type f -name '*.sql' | sort | while read -r sql_file; do
		file_name=$(basename "$sql_file")
		if contains "$file_name" "${EXCLUDE_FILES[@]}"; then
			echo "Skipping file $file_name..."
			continue
		fi

		echo "Executing $sql_file..."
		sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -d "$MY_SQLSERVER_DATABASE" -i "$sql_file"
		if [ $? -ne 0 ]; then
			echo "Error executing $sql_file. Exiting."
			exit 1
		fi
	done
done

