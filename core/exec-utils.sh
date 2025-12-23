#!/bin/bash

# Finds an executable in the system PATH and returns its full path
# Args:
#   $1: The name of the executable to find
# Returns:
#   0 if executable is found, 1 if not found
# Output:
#   Prints the full path of the executable if found
find_executable() {
    local name="$1"

    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi

    return 1
}

# Ensures that a required executable exists in PATH, exits if not found
# Args:
#   $1: The name of the executable to require
#   $2: Optional hint message to show if executable is not found
# Returns:
#   Exits the script with code 1 if executable is not found
# Output:
#   Prints the full path of the executable if found
#   Prints error messages and exits if not found
require_executable() {
    local name="$1"
    local hint="${2:-}"

    if ! find_executable "$name" >/dev/null; then
        log_error "Required executable '$name' not found in PATH"
        if [[ -n "$hint" ]]; then
            log_error "Hint: $hint"
        fi
        exit 1
    fi

    find_executable "$name"
}

# Collects executable files from a target path (file or directory)
# For directories, recursively finds all .sql files and returns them sorted
# Args:
#   $1: Target path (file or directory)
# Returns:
#   0 on success, 1 on error
# Output:
#   Prints one file path per line, sorted if directory
collect_exec_files() {
    local target="$1"
    local files=()

    if [[ ! -e "$target" ]]; then
        log_error "Path does not exist: $target"
        return 1
    fi

    if [[ -f "$target" ]]; then
        # Single file
        echo "$target"
    elif [[ -d "$target" ]]; then
        # Directory - collect and sort files recursively
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$target" -type f -name "*.sql" -print0 | sort -z)

        if [[ ${#files[@]} -eq 0 ]]; then
            log_warn "No SQL files found in directory: $target"
            return 0
        fi

        printf '%s\n' "${files[@]}"
    else
        log_error "Invalid target: $target (not a file or directory)"
        return 1
    fi
}

# Creates a temporary file, executes a callback with it, then cleans it up
# Args:
#   $@: Command and arguments to execute, with temp file path as last argument
# Returns:
#   Returns the exit code of the executed command
with_tempfile() {
    local tmp
    tmp=$(mktemp)
    "$@" "$tmp"
    rm -f "$tmp"
}

# Prints an execution plan showing the files that will be processed
# Args:
#   $@: Array of file paths to be executed
# Returns:
#   Always returns 0
# Output:
#   Prints numbered list of files with total count
print_exec_plan() {
    local files=("$@")
    local total=${#files[@]}

    if [[ $total -eq 0 ]]; then
        log_info "No files to execute"
        return 0
    fi

    log_info "Execution plan ($total files):"
    for i in "${!files[@]}"; do
        printf "[%d/%d] %s\n" $((i+1)) "$total" "$(basename "${files[i]}")"
    done
}

# Executes a command and aborts the script if it fails
# Args:
#   $@: Command and arguments to execute
# Returns:
#   Exits the script with code 1 if command fails
# Output:
#   Logs debug information and error messages
run_or_abort() {
    log_debug "Executing: $*"
    if ! "$@"; then
        log_error "Command failed: $*"
        log_error "Aborting execution due to error"
        exit 1
    fi
}

# Processes each file in a list using a callback function, aborting on any failure
# Args:
#   files... -- callback_function
#   Files to process followed by -- and then the callback function name
# Returns:
#   Exits the script with code 1 if any callback execution fails
# Usage:
#   run_each_or_abort file1.sql file2.sql -- process_sql_file
run_each_or_abort() {
    local files=()
    local callback=""

    # Parse files until we hit --
    while [[ $# -gt 0 && "$1" != "--" ]]; do
        files+=("$1")
        shift
    done

    if [[ "$1" == "--" ]]; then
        shift
        callback="$1"
    else
        log_error "Usage: run_each_or_abort <files...> -- <callback>"
        return 1
    fi

    local total=${#files[@]}
    for i in "${!files[@]}"; do
        local file="${files[i]}"
        log_info "[$((i+1))/$total] Processing: $(basename "$file")"

        if ! "$callback" "$file"; then
            log_error "Failed to process: $file"
            exit 1
        fi

        log_debug "Successfully processed: $file"
    done
}

# Verifies SQL execution results and reports potential issues
# Args:
#   $1: Exit code from SQL execution
#   $2: Output from SQL execution
#   $3: SQL file path that was executed
# Returns:
#   1 if execution failed, 0 if successful (may still warn about issues)
verify_sql_result() {
    local exit_code="$1"
    local output="$2"
    local file="$3"

    if [[ $exit_code -ne 0 ]]; then
        log_error "SQL execution failed for: $(basename "$file")"
        log_error "Output: $output"
        return 1
    fi

    # Check for common SQL error patterns
    if echo "$output" | grep -qi "error\|failed\|exception"; then
        log_warn "Potential issues detected in output from: $(basename "$file")"
        log_warn "Output: $output"
    fi
}

# Executes a series of operations within a database transaction
# Automatically commits on success or rolls back on failure
# Args:
#   $1: Database command to use for transaction control (e.g., "psql -c")
#   $@: Operations to execute within the transaction
# Returns:
#   0 on success, 1 on failure (after rollback)
with_transaction() {
    local db_command="$1"
    shift

    log_debug "Starting transaction"
    run_or_abort "$db_command" "BEGIN;"

    if "$@"; then
        log_debug "Committing transaction"
        run_or_abort "$db_command" "COMMIT;"
    else
        log_error "Rolling back transaction due to error"
        "$db_command" "ROLLBACK;" 2>/dev/null || true
        return 1
    fi
}

# Displays progress information for file processing
# Args:
#   $1: Current file number being processed
#   $2: Total number of files to process
#   $3: Current filename being processed
# Output:
#   Prints a progress bar with percentage and file information
#   Uses carriage return for in-place updates, newline at completion
show_progress() {
    local current="$1"
    local total="$2"
    local filename="$3"

    local percent=$((current * 100 / total))
    printf "\r[%3d%%] [%d/%d] %s" "$percent" "$current" "$total" "$(basename "$filename")"

    if [[ $current -eq $total ]]; then
        echo  # newline at the end
    fi
}
