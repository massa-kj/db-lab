#!/bin/bash

# tests/unit/test_lib.sh - Unit tests for core/lib.sh
# Tests core utility functions and validation logic

set -euo pipefail

# Source test framework and module under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helper.sh"
source "${SCRIPT_DIR}/../../core/lib.sh"

# Test validate_instance_name function
test_validate_instance_name() {
    # Valid instance names
    assert_success "validate_instance_name 'pg16'" "Valid alphanumeric name"
    assert_success "validate_instance_name 'test-db'" "Valid name with hyphen"
    assert_success "validate_instance_name 'my_instance'" "Valid name with underscore"
    assert_success "validate_instance_name 'a'" "Single character name"
    assert_success "validate_instance_name '1test'" "Name starting with number"
    
    # Invalid instance names
    assert_failure "validate_instance_name 'Test'" "Uppercase not allowed"
    assert_failure "validate_instance_name 'test db'" "Spaces not allowed"
    assert_failure "validate_instance_name 'test@db'" "Special characters not allowed"
    assert_failure "validate_instance_name '-test'" "Cannot start with hyphen"
    assert_failure "validate_instance_name ''" "Empty name not allowed"
    assert_failure "validate_instance_name 'very_long_name_that_exceeds_the_limit_of_thirty_one_characters'" "Too long name"
}

# Test validate_engine_name function
test_validate_engine_name() {
    # Valid engine names
    assert_success "validate_engine_name 'postgres'" "Valid engine name"
    assert_success "validate_engine_name 'mysql'" "Valid engine name"
    assert_success "validate_engine_name 'redis'" "Valid engine name"
    assert_success "validate_engine_name 'postgres14'" "Engine with number"
    
    # Invalid engine names
    assert_failure "validate_engine_name 'postgres-sql'" "Hyphen not allowed"
    assert_failure "validate_engine_name 'PostgreSQL'" "Uppercase not allowed"
    assert_failure "validate_engine_name 'post gres'" "Spaces not allowed"
    assert_failure "validate_engine_name ''" "Empty name not allowed"
}

# Test mask_sensitive function
test_mask_sensitive() {
    local masked_password
    masked_password=$(mask_sensitive "password=secret123")
    assert_contains "$masked_password" "****" "Password should be masked"
    assert_not_equals "$masked_password" "password=secret123" "Original password should not appear"
    
    local masked_url
    masked_url=$(mask_sensitive "postgres://user:pass@host:5432/db")
    assert_contains "$masked_url" "****" "URL credentials should be masked"
    
    local masked_env
    masked_env=$(mask_sensitive "DBLAB_PG_PASSWORD=secret")
    assert_contains "$masked_env" "****" "Environment password should be masked"
    
    local normal_text
    normal_text=$(mask_sensitive "normal text without secrets")
    assert_equals "$normal_text" "normal text without secrets" "Normal text should not be changed"
}

# Test get_data_dir function
test_get_data_dir() {
    local data_dir
    data_dir=$(get_data_dir "postgres" "pg16")
    assert_contains "$data_dir" "postgres/pg16" "Data dir should contain engine and instance"
    assert_contains "$data_dir" "$DBLAB_BASE_DIR" "Data dir should be under base dir"
    
    # Test with different instances
    local data_dir2
    data_dir2=$(get_data_dir "mysql" "mysql8")
    assert_not_equals "$data_dir" "$data_dir2" "Different instances should have different dirs"
    
    # Test error cases
    assert_failure "get_data_dir '' 'instance'" "Empty engine should fail"
    assert_failure "get_data_dir 'engine' ''" "Empty instance should fail"
}

# Test ensure_dir function
test_ensure_dir() {
    local test_dir="$TEST_TMP_DIR/test_ensure_dir"
    
    # Directory should be created
    assert_success "ensure_dir '$test_dir'" "ensure_dir should succeed"
    assert_dir_exists "$test_dir" "Directory should be created"
    
    # Should not fail if directory already exists
    assert_success "ensure_dir '$test_dir'" "ensure_dir should be idempotent"
    
    # Test nested directory creation
    local nested_dir="$TEST_TMP_DIR/nested/deep/dir"
    assert_success "ensure_dir '$nested_dir'" "Should create nested directories"
    assert_dir_exists "$nested_dir" "Nested directory should exist"
}

# Test safe_rm function
test_safe_rm() {
    # Create test file and directory
    local test_file="$TEST_TMP_DIR/test_file"
    local test_dir="$TEST_TMP_DIR/test_dir"
    
    echo "test" > "$test_file"
    mkdir -p "$test_dir"
    
    # Should remove file
    assert_success "safe_rm '$test_file'" "Should remove file"
    assert_failure "test -f '$test_file'" "File should be removed"
    
    # Should remove directory
    assert_success "safe_rm '$test_dir'" "Should remove directory"
    assert_failure "test -d '$test_dir'" "Directory should be removed"
    
    # Should not fail for non-existent path
    assert_success "safe_rm '$TEST_TMP_DIR/non_existent'" "Should not fail for non-existent path"
    
    # Should refuse dangerous paths
    assert_failure "safe_rm '/'" "Should refuse to remove root"
    assert_failure "safe_rm '$HOME'" "Should refuse to remove home directory"
    assert_failure "safe_rm ''" "Should refuse empty path"
}

# Test get_abs_path function
test_get_abs_path() {
    local abs_path
    abs_path=$(get_abs_path "/absolute/path")
    assert_equals "$abs_path" "/absolute/path" "Absolute path should remain unchanged"
    
    # Test relative path (this will vary based on current directory)
    local rel_path
    rel_path=$(get_abs_path "relative/path")
    assert_contains "$rel_path" "/relative/path" "Relative path should be made absolute"
    assert_equals "${rel_path:0:1}" "/" "Path should start with /"
}

# Test command_exists function
test_command_exists() {
    # Test with commands that should exist
    assert_success "command_exists 'bash'" "bash should exist"
    assert_success "command_exists 'ls'" "ls should exist"
    assert_success "command_exists 'echo'" "echo should exist"
    
    # Test with command that should not exist
    assert_failure "command_exists 'nonexistent_command_12345'" "Non-existent command should fail"
}

# Test init_dblab function
test_init_dblab() {
    # Should create base directory
    assert_success "init_dblab" "init_dblab should succeed"
    assert_dir_exists "$DBLAB_BASE_DIR" "Base directory should be created"
    
    # Should be idempotent
    assert_success "init_dblab" "init_dblab should be idempotent"
}

# Test logging functions (basic test - just ensure they don't crash)
test_logging_functions() {
    # Mock DBLAB_LOG_LEVEL to test different levels
    local original_log_level="$DBLAB_LOG_LEVEL"
    
    DBLAB_LOG_LEVEL="debug"
    assert_success "log_debug 'test debug message'" "log_debug should not crash"
    assert_success "log_info 'test info message'" "log_info should not crash"
    assert_success "log_warn 'test warn message'" "log_warn should not crash"
    assert_success "log_error 'test error message'" "log_error should not crash"
    
    # Restore original log level
    DBLAB_LOG_LEVEL="$original_log_level"
}

# Run all tests
main() {
    run_test_suite "Core Library Tests" \
        test_validate_instance_name \
        test_validate_engine_name \
        test_mask_sensitive \
        test_get_data_dir \
        test_ensure_dir \
        test_safe_rm \
        test_get_abs_path \
        test_command_exists \
        test_init_dblab \
        test_logging_functions
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
