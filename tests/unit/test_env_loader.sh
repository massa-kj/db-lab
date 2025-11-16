#!/bin/bash

# tests/unit/test_env_loader.sh - Unit tests for core/env_loader.sh
# Tests environment loading and priority system

set -euo pipefail

# Source test framework and modules under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helper.sh"
source "${SCRIPT_DIR}/../../core/lib.sh"
source "${SCRIPT_DIR}/../../core/env_loader.sh"

# Test get_env and set core defaults
test_core_defaults() {
    # Reset environment
    reset_environment
    set_core_defaults
    
    # Test core defaults are set
    local base_dir
    base_dir=$(get_env "DBLAB_BASE_DIR")
    assert_not_equals "$base_dir" "" "DBLAB_BASE_DIR should be set"
    
    local log_level
    log_level=$(get_env "DBLAB_LOG_LEVEL")
    assert_not_equals "$log_level" "" "DBLAB_LOG_LEVEL should be set"
    
    local ephemeral
    ephemeral=$(get_env "DBLAB_EPHEMERAL")
    assert_equals "$ephemeral" "false" "DBLAB_EPHEMERAL should default to false"
}

# Test loading environment files
test_load_env_files() {
    # Create test env file
    local test_env_file="$TEST_TMP_DIR/test.env"
    cat > "$test_env_file" << EOF
DBLAB_PG_VERSION=16
DBLAB_PG_USER=testuser
DBLAB_PG_PASSWORD=testpass
DBLAB_PG_DATABASE=testdb
EOF

    # Reset and load environment
    reset_environment
    set_core_defaults
    load_env_files "$test_env_file"
    
    # Test values are loaded
    assert_equals "$(get_env 'DBLAB_PG_VERSION')" "16" "Version should be loaded"
    assert_equals "$(get_env 'DBLAB_PG_USER')" "testuser" "User should be loaded"
    assert_equals "$(get_env 'DBLAB_PG_PASSWORD')" "testpass" "Password should be loaded"
    assert_equals "$(get_env 'DBLAB_PG_DATABASE')" "testdb" "Database should be loaded"
}

# Test env file with comments and empty lines
test_env_file_parsing() {
    local test_env_file="$TEST_TMP_DIR/test_comments.env"
    cat > "$test_env_file" << EOF
# This is a comment
DBLAB_PG_VERSION=16

# Another comment
DBLAB_PG_USER=testuser

   # Indented comment
DBLAB_PG_DATABASE=testdb

EOF

    reset_environment
    set_core_defaults
    load_env_files "$test_env_file"
    
    assert_equals "$(get_env 'DBLAB_PG_VERSION')" "16" "Should parse version despite comments"
    assert_equals "$(get_env 'DBLAB_PG_USER')" "testuser" "Should parse user despite empty lines"
    assert_equals "$(get_env 'DBLAB_PG_DATABASE')" "testdb" "Should parse database despite indented comments"
}

# Test metadata loading
test_load_metadata_defaults() {
    # Create test metadata file
    local test_metadata="$TEST_TMP_DIR/metadata.yml"
    cat > "$test_metadata" << EOF
engine: postgres

defaults:
  DBLAB_PG_USER: postgres
  DBLAB_PG_DATABASE: app
  DBLAB_PG_PORT: 5432

validation:
  user_regex: "^[a-zA-Z0-9_]+$"
EOF

    reset_environment
    set_core_defaults
    load_metadata_defaults "$test_metadata"
    
    assert_equals "$(get_env 'DBLAB_PG_USER')" "postgres" "Metadata user should be loaded"
    assert_equals "$(get_env 'DBLAB_PG_DATABASE')" "app" "Metadata database should be loaded"
    assert_equals "$(get_env 'DBLAB_PG_PORT')" "5432" "Metadata port should be loaded"
}

# Test host environment loading
test_load_host_environment() {
    # Set test environment variables
    export DBLAB_TEST_VAR="host_value"
    export DBLAB_ANOTHER_VAR="another_host_value"
    export NON_DBLAB_VAR="should_be_ignored"
    
    reset_environment
    set_core_defaults
    load_host_environment
    
    assert_equals "$(get_env 'DBLAB_TEST_VAR')" "host_value" "Host env var should be loaded"
    assert_equals "$(get_env 'DBLAB_ANOTHER_VAR')" "another_host_value" "Another host env var should be loaded"
    assert_equals "$(get_env 'NON_DBLAB_VAR')" "" "Non-DBLAB vars should be ignored"
    
    # Cleanup
    unset DBLAB_TEST_VAR DBLAB_ANOTHER_VAR NON_DBLAB_VAR
}

# Test CLI overrides
test_apply_cli_overrides() {
    reset_environment
    set_core_defaults
    
    # Apply CLI overrides
    apply_cli_overrides "DBLAB_PG_VERSION=17" "DBLAB_PG_USER=cliuser"
    
    assert_equals "$(get_env 'DBLAB_PG_VERSION')" "17" "CLI version override should work"
    assert_equals "$(get_env 'DBLAB_PG_USER')" "cliuser" "CLI user override should work"
}

# Test priority system (later sources override earlier ones)
test_priority_system() {
    # Create metadata file
    local metadata_file="$TEST_TMP_DIR/metadata.yml"
    cat > "$metadata_file" << EOF
defaults:
  DBLAB_PG_VERSION: "14"
  DBLAB_PG_USER: metadata_user
EOF

    # Create env file
    local env_file="$TEST_TMP_DIR/priority.env"
    cat > "$env_file" << EOF
DBLAB_PG_VERSION=15
DBLAB_PG_DATABASE=env_database
EOF

    # Set host environment
    export DBLAB_PG_VERSION="16"
    
    # Load in order: metadata -> env file -> host environment -> CLI
    reset_environment
    set_core_defaults
    load_metadata_defaults "$metadata_file"
    load_env_files "$env_file"
    load_host_environment
    apply_cli_overrides "DBLAB_PG_USER=cli_user"
    
    # Test priority: CLI > host > env file > metadata > core
    assert_equals "$(get_env 'DBLAB_PG_VERSION')" "16" "Host env should override env file and metadata"
    assert_equals "$(get_env 'DBLAB_PG_USER')" "cli_user" "CLI should override all others"
    assert_equals "$(get_env 'DBLAB_PG_DATABASE')" "env_database" "Env file value should be used when no override"
    
    unset DBLAB_PG_VERSION
}

# Test validate_required_env
test_validate_required_env() {
    reset_environment
    set_core_defaults
    
    # Set some required vars
    apply_cli_overrides "DBLAB_PG_VERSION=16" "DBLAB_PG_USER=testuser"
    
    # Should pass when all required vars are present
    assert_success "validate_required_env 'DBLAB_PG_VERSION' 'DBLAB_PG_USER'" "Should pass with all required vars"
    
    # Should fail when required vars are missing
    assert_failure "validate_required_env 'DBLAB_PG_VERSION' 'DBLAB_PG_USER' 'DBLAB_MISSING_VAR'" "Should fail with missing var"
}

# Test get_env with default values
test_get_env_with_defaults() {
    reset_environment
    set_core_defaults
    
    # Test existing value
    apply_cli_overrides "DBLAB_TEST_VAR=existing_value"
    assert_equals "$(get_env 'DBLAB_TEST_VAR' 'default_value')" "existing_value" "Should return existing value"
    
    # Test default value for missing var
    assert_equals "$(get_env 'DBLAB_MISSING_VAR' 'default_value')" "default_value" "Should return default for missing var"
    
    # Test empty default
    assert_equals "$(get_env 'DBLAB_MISSING_VAR')" "" "Should return empty string when no default"
}

# Test get_env_source tracking
test_get_env_source() {
    reset_environment
    set_core_defaults
    
    # Test core source
    local core_source
    core_source=$(get_env_source "DBLAB_LOG_LEVEL")
    assert_equals "$core_source" "core" "Core defaults should have core source"
    
    # Test CLI source
    apply_cli_overrides "DBLAB_TEST_VAR=cli_value"
    local cli_source
    cli_source=$(get_env_source "DBLAB_TEST_VAR")
    assert_equals "$cli_source" "cli" "CLI overrides should have cli source"
}

# Test complete load_environment function
test_load_environment() {
    # Create metadata and env files
    local metadata_file="$TEST_TMP_DIR/complete_metadata.yml"
    cat > "$metadata_file" << EOF
defaults:
  DBLAB_PG_USER: postgres
  DBLAB_PG_PORT: 5432
EOF

    local env_file="$TEST_TMP_DIR/complete.env"
    cat > "$env_file" << EOF
DBLAB_PG_VERSION=16
DBLAB_PG_PASSWORD=secret
EOF

    # Test complete loading
    reset_environment
    load_environment "$metadata_file" "$env_file"
    
    # Verify all layers are loaded
    assert_not_equals "$(get_env 'DBLAB_BASE_DIR')" "" "Core defaults should be loaded"
    assert_equals "$(get_env 'DBLAB_PG_USER')" "postgres" "Metadata defaults should be loaded"
    assert_equals "$(get_env 'DBLAB_PG_VERSION')" "16" "Env file should be loaded"
}

# Run all tests
main() {
    run_test_suite "Environment Loader Tests" \
        test_core_defaults \
        test_load_env_files \
        test_env_file_parsing \
        test_load_metadata_defaults \
        test_load_host_environment \
        test_apply_cli_overrides \
        test_priority_system \
        test_validate_required_env \
        test_get_env_with_defaults \
        test_get_env_source \
        test_load_environment
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
