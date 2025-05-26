#!/bin/bash

set -ue

# Function to check if a value is in an array
__contains() {
	local e match="$1"
	shift
	for e; do [[ "$e" == "$match" ]] && return 0; done
	return 1
}

# extract_sql_files
# Recursively finds and lists all .sql files in the given directory ($1), 
# excluding directories listed in the array referenced by $2 and files listed 
# in the array referenced by $3. The function prints the path of each .sql file 
# that is not excluded.
#
# Arguments:
#   $1 - Root directory to search for .sql files.
#   $2 - Name of array variable containing directory names to exclude.
#   $3 - Name of array variable containing file names to exclude.
#
# Usage:
#   EXCLUDE_DIRS=("dir1" "dir2")
#   EXCLUDE_FILES=("file1.sql" "file2.sql")
#   extract_sql_files "/path/to/sql" EXCLUDE_DIRS[@] EXCLUDE_FILES[@]
extract_sql_files() {
	local SQL_PATH="$1"
	local EXCLUDE_DIRS=("${!2}")
	local EXCLUDE_FILES=("${!3}")

	# echo "Running SQL files in $SQL_PATH..."
	find "$SQL_PATH" -type d | sort | while read -r dir; do
		dir_name=$(basename "$dir")
		if __contains "$dir_name" "${EXCLUDE_DIRS[@]}"; then
			# echo "Skipping directory $dir..."
			continue
		fi

		find "$dir" -maxdepth 1 -type f -name '*.sql' | sort | while read -r sql_file; do
			file_name=$(basename "$sql_file")
			if __contains "$file_name" "${EXCLUDE_FILES[@]}"; then
				# echo "Skipping file $file_name..."
				continue
			fi

			# echo "Executing $sql_file..."
			echo "$sql_file"
		done
	done
}

# validate_env_vars checks that all required environment variables are set and non-empty.
# Arguments:
#   List of environment variable names to validate.
# Exits with status 1 and prints an error message if any variable is unset or empty.
validate_env_vars() {
	local REQUIRED_VARS=("$@")
	for var in "${REQUIRED_VARS[@]}"; do
		if [ -z "${!var}" ]; then
			echo "Error: Environment variable $var is not set or is empty."
			exit 1
		fi
	done
}
