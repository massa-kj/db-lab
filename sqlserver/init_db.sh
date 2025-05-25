#!/bin/bash

set -e

SQL_PATH="./sql/init"

# Read environment variables from .env file
export $(grep -v '^#' .env | xargs)

echo "Waiting for SQL Server to start..."
until sqlcmd -S ${MY_SQLSERVER_SERVERNAME} -U ${MY_SQLSERVER_SA_USERNAME} -P ${MY_SQLSERVER_SA_PASSWORD} -Q "SELECT 1" &> /dev/null; do
	sleep 1
done

echo "Creating database {$MY_SQLSERVER_DATABASE} if it does not exist..."
sqlcmd -S ${MY_SQLSERVER_SERVERNAME} -U ${MY_SQLSERVER_SA_USERNAME} -P ${MY_SQLSERVER_SA_PASSWORD} -Q "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = N'${MY_SQLSERVER_DATABASE}') CREATE DATABASE [${MY_SQLSERVER_DATABASE}]"

echo "Running SQL files in ./sql/init..."
for sql_file in $(ls "$SQL_PATH"/*.sql | sort); do
	echo "Executing $sql_file..."
	sqlcmd -S ${MY_SQLSERVER_SERVERNAME} -U ${MY_SQLSERVER_SA_USERNAME} -P ${MY_SQLSERVER_SA_PASSWORD} -d ${MY_SQLSERVER_DATABASE} -i "$sql_file"
	if [ $? -ne 0 ]; then
		echo "Error executing $sql_file. Exiting."
		exit 1
	fi
done

