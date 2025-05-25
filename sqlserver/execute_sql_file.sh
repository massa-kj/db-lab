#!/bin/bash

set -e

# Read environment variables from .env file
export $(grep -v '^#' .env | xargs)

# Check if at least one SQL file path is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <path_to_sql_file1> [<path_to_sql_file2> ...]"
    exit 1
fi

# Iterate over all provided SQL files
for SQL_FILE in "$@"; do
    # Check if the file exists
    if [ ! -f "$SQL_FILE" ]; then
        echo "File $SQL_FILE does not exist. Skipping."
        continue
    fi

    # Execute the SQL file
    echo "Executing $SQL_FILE..."
    sqlcmd -S ${MY_SQLSERVER_SERVERNAME} -U ${MY_SQLSERVER_SA_USERNAME} -P ${MY_SQLSERVER_SA_PASSWORD} -d ${MY_SQLSERVER_DATABASE} -i "$SQL_FILE"
    if [ $? -ne 0 ]; then
        echo "Error executing $SQL_FILE. Exiting."
        exit 1
    fi

    echo "SQL file $SQL_FILE executed successfully."
done

