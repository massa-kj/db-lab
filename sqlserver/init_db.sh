#!/bin/bash

set -ue

source ./util.sh

# Read environment variables from .env file
export $(grep -v '^#' .env | xargs)
# Validate required environment variables
REQUIRED_VARS=(
	"MY_SQLSERVER_SERVERNAME"
	"MY_SQLSERVER_SA_USERNAME"
	"MY_SQLSERVER_SA_PASSWORD"
	"MY_SQLSERVER_INIT_DATABASE"
	"MY_SQLSERVER_INIT_SQL_PATH"
)
validate_env_vars "${REQUIRED_VARS[@]}"

EXCLUDE_DIRS=($(echo "${MY_SQLSERVER_INIT_EXCLUDE_DIRS}" | tr ',' ' '))
echo "Excluding directories: ${EXCLUDE_DIRS[*]}"
EXCLUDE_FILES=($(echo "${MY_SQLSERVER_INIT_EXCLUDE_FILES}" | tr ',' ' '))
echo "Excluding files: ${EXCLUDE_FILES[*]}"

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
echo "Creating database ${MY_SQLSERVER_INIT_DATABASE} if it does not exist..."
sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -Q "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = N'${MY_SQLSERVER_INIT_DATABASE}') CREATE DATABASE [${MY_SQLSERVER_INIT_DATABASE}]"

# Execute SQL files recursively, directory-first, sorted by name
extract_sql_files "$MY_SQLSERVER_INIT_SQL_PATH" EXCLUDE_DIRS[@] EXCLUDE_FILES[@] | while read -r sql_file; do
	sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -d "$MY_SQLSERVER_INIT_DATABASE" -i "$sql_file"
	echo "Executed: $sql_file"
done

