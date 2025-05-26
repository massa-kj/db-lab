#!/bin/bash

set -ue

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
