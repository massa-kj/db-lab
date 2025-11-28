#!/bin/bash

# tests/unit/test_instance_loader.sh - Unit tests for core/instance_loader.sh
# Tests instance management and YAML handling

set -euo pipefail

# Source test framework and modules under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helper.sh"
source "${SCRIPT_DIR}/../../core/lib.sh"
source "${SCRIPT_DIR}/../../core/instance_loader.sh"

# Test get_container_name function
test_get_container_name() {
    local container_name
    container_name=$(get_container_name "postgres" "pg16")
    assert_equals "$container_name" "dblab_postgres_pg16" "Container name should follow naming convention"
    
    local mysql_name
    mysql_name=$(get_container_name "mysql" "mysql8")
    assert_equals "$mysql_name" "dblab_mysql_mysql8" "Different engine should have different prefix"
}

# Test get_network_name function
test_get_network_name() {
    local isolated_net
    isolated_net=$(get_network_name "postgres" "pg16" "isolated")
    assert_equals "$isolated_net" "dblab_postgres_pg16_net" "Isolated network should include instance"
    
    local shared_net
    shared_net=$(get_network_name "postgres" "pg16" "engine-shared")
    assert_equals "$shared_net" "dblab_postgres_shared_net" "Engine-shared network should not include instance"
    
    local default_net
    default_net=$(get_network_name "postgres" "pg16")
    assert_equals "$default_net" "dblab_postgres_pg16_net" "Default should be isolated"
}

# Test get_instance_file function
test_get_instance_file() {
    local instance_file
    instance_file=$(get_instance_file "postgres" "pg16")
    assert_contains "$instance_file" "postgres/pg16/instance.yml" "Instance file should be in correct path"
    assert_contains "$instance_file" "$DBLAB_BASE_DIR" "Instance file should be under base dir"
}

# Test instance_exists function
test_instance_exists() {
    # Should return false for non-existent instance
    assert_failure "instance_exists 'postgres' 'nonexistent'" "Non-existent instance should return false"
    
    # Create a test instance file
    local test_instance_dir="$DBLAB_BASE_DIR/postgres/testinstance"
    local test_instance_file="$test_instance_dir/instance.yml"
    
    mkdir -p "$test_instance_dir"
    echo "engine: postgres" > "$test_instance_file"
    
    # Should return true for existing instance
    assert_success "instance_exists 'postgres' 'testinstance'" "Existing instance should return true"
}

# Test network name generation edge cases
test_network_name_edge_cases() {
    # Test unknown network mode
    assert_failure "get_network_name 'postgres' 'test' 'unknown_mode'" "Should fail with unknown network mode"
    
    # Test with different engines
    local pg_shared
    pg_shared=$(get_network_name "postgres" "any" "engine-shared")
    local mysql_shared
    mysql_shared=$(get_network_name "mysql" "any" "engine-shared")
    
    assert_not_equals "$pg_shared" "$mysql_shared" "Different engines should have different shared networks"
}

# Test instance validation
test_instance_validation() {
    # These should fail due to validation in get_instance_file
    assert_failure "get_instance_file 'invalid@engine' 'test'" "Invalid engine name should be rejected"
    assert_failure "get_instance_file 'postgres' 'Invalid Instance'" "Invalid instance name should be rejected"
    assert_failure "get_instance_file '' 'test'" "Empty engine should be rejected"
    assert_failure "get_instance_file 'postgres' ''" "Empty instance should be rejected"
}

# Run all tests
main() {
    run_test_suite "Instance Loader Tests" \
        test_get_container_name \
        test_get_network_name \
        test_get_instance_file \
        test_instance_exists \
        test_network_name_edge_cases \
        test_instance_validation
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
