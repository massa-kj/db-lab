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

	# If SQL_PATH is a file, echo its path and exit
	if [ -f "$SQL_PATH" ] && [[ "$SQL_PATH" == *.sql ]]; then
		echo "$SQL_PATH"
		return
	fi

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

# wait_for_db runs a database readiness check command repeatedly until it succeeds or a timeout occurs.
# Arguments:
#   $1 - The command to check database readiness (should return 0 if ready).
#   $2 - (Optional) Maximum number of retries (default: 10).
# Returns:
#   0 if the database becomes ready within the retry limit, 1 otherwise.
wait_for_db() {
    local check_cmd="$1"
    local max_retries="${2:-10}"
    for i in $(seq 1 "$max_retries"); do
        echo "[$i/$max_retries] Waiting for DB readiness..."
        if eval "$check_cmd"; then
            echo "DB is ready."
            return 0
        fi
        sleep 1
    done
    echo "Timeout waiting for DB"
    return 1
}

# load_env_file loads environment variables from a specified .env file.
# Usage: load_env_file [env_file]
# - If ENV_DISABLE_DOTENV is set to "true", loading is skipped.
# - If no file is specified, defaults to ".env".
# - Ignores blank lines and lines starting with '#'.
# - Only lines in KEY=VALUE format are processed.
# - Keys must match shell variable naming rules.
# - Variables already set in the environment are not overwritten.
load_env_file() {
    env_file="${1:-.env}"

    if [ "${ENV_DISABLE_DOTENV:-}" = "true" ]; then
        echo "Skip loading .env because ENV_DISABLE_DOTENV=true"
        return 0
    fi

    if [ ! -f "$env_file" ]; then
        echo ".env file not found: $env_file"
        return 0
    fi

    echo "Loading environment variables from .env file: $env_file"

    while IFS= read -r line || [ -n "$line" ]; do
        # Blank lines and leading # characters are skipped
        case "$line" in
            ''|\#*) continue ;;
        esac

        # Only simple KEY=VALUE is allowed
        case "$line" in
            *=*)
                key=$(printf '%s' "$line" | awk -F= '{print $1}')
                value=$(printf '%s' "$line" | awk -F= '{print $2}')
                # remove leading and trailing whitespace
                key=$(printf '%s' "$key" | awk '{$1=$1;print}')
                value=$(printf '%s' "$value" | awk '{$1=$1;print}')
                # validate key
                if ! printf '%s' "$key" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
                    continue
                fi
                # Skip if already set
                eval "is_set=\${$key+x}"
                if [ -z "$is_set" ]; then
                    export "$key=$value"
                fi
                ;;
            *)
                continue
                ;;
        esac
    done < "$env_file"
}

