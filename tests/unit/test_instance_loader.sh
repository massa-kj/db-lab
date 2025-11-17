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

# Test create_instance function
test_create_instance() {
    # Create new instance
    assert_success "create_instance 'postgres' 'test_pg' '16' 'postgres' 'secret' 'testdb' 'isolated' 'false'" "Should create instance successfully"
    
    # Verify instance exists
    assert_success "instance_exists 'postgres' 'test_pg'" "Created instance should exist"
    
    # Verify instance file structure
    local instance_file
    instance_file=$(get_instance_file "postgres" "test_pg")
    assert_file_exists "$instance_file" "Instance YAML file should exist"
    
    # Verify required directories
    local data_dir="$DBLAB_BASE_DIR/postgres/test_pg"
    assert_dir_exists "$data_dir/data" "Data directory should be created"
    assert_dir_exists "$data_dir/config" "Config directory should be created"
    assert_dir_exists "$data_dir/logs" "Logs directory should be created"
    
    # Verify instance file content
    assert_success "grep -q 'engine: postgres' '$instance_file'" "Instance file should contain engine"
    assert_success "grep -q 'instance: test_pg' '$instance_file'" "Instance file should contain instance name"
    assert_success "grep -q 'version: \"16\"' '$instance_file'" "Instance file should contain version"
    
    # Should fail to create duplicate instance
    assert_failure "create_instance 'postgres' 'test_pg' '16' 'postgres' 'secret' 'testdb' 'isolated' 'false'" "Should fail to create duplicate instance"
}

# Test load_instance function
test_load_instance() {
    # Create instance first
    create_instance "postgres" "load_test" "16" "testuser" "testpass" "testdb" "isolated" "false"
    
    # Load instance
    assert_success "load_instance 'postgres' 'load_test'" "Should load existing instance"
    
    # Test loaded values
    assert_equals "$(get_instance_config 'engine')" "postgres" "Should load engine correctly"
    assert_equals "$(get_instance_config 'instance')" "load_test" "Should load instance name correctly"
    assert_equals "$(get_instance_config 'version')" "16" "Should load version correctly"
    
    # Should fail to load non-existent instance
    assert_failure "load_instance 'postgres' 'nonexistent'" "Should fail to load non-existent instance"
}

# Test get_instance_config function
test_get_instance_config() {
    # Create and load instance
    create_instance "postgres" "config_test" "15" "configuser" "configpass" "configdb" "engine-shared" "true"
    load_instance "postgres" "config_test"
    
    # Test basic config retrieval
    assert_equals "$(get_instance_config 'user')" "configuser" "Should get user config"
    assert_equals "$(get_instance_config 'database')" "configdb" "Should get database config"
    assert_equals "$(get_instance_config 'mode')" "engine-shared" "Should get network mode config"
    
    # Test default value
    assert_equals "$(get_instance_config 'nonexistent' 'default_val')" "default_val" "Should return default for missing config"
    
    # Test empty default
    assert_equals "$(get_instance_config 'nonexistent')" "" "Should return empty for missing config with no default"
}

# Test update_instance_state function
test_update_instance_state() {
    # Create and load instance
    create_instance "postgres" "state_test" "16" "stateuser" "statepass" "statedb" "isolated" "false"
    
    # Update state
    assert_success "update_instance_state 'postgres' 'state_test' 'status' 'running'" "Should update status"
    
    # Load instance again and verify
    load_instance "postgres" "state_test"
    assert_equals "$(get_instance_config 'status')" "running" "Status should be updated"
    
    # Test updating last_up (time-based, just check it doesn't crash)
    assert_success "update_instance_state 'postgres' 'state_test' 'last_up' ''" "Should update last_up timestamp"
}

# Test remove_instance function
test_remove_instance() {
    # Create instance
    create_instance "postgres" "remove_test" "16" "removeuser" "removepass" "removedb" "isolated" "false"
    
    # Verify it exists
    assert_success "instance_exists 'postgres' 'remove_test'" "Instance should exist before removal"
    
    # Remove with force
    assert_success "remove_instance 'postgres' 'remove_test' 'true'" "Should remove instance with force"
    
    # Verify it's gone
    assert_failure "instance_exists 'postgres' 'remove_test'" "Instance should not exist after removal"
    
    # Should not fail to remove non-existent instance
    assert_success "remove_instance 'postgres' 'nonexistent' 'true'" "Should not fail to remove non-existent instance"
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

# Test YAML file structure and content
test_yaml_structure() {
    # Create instance
    create_instance "postgres" "yaml_test" "16" "yamluser" "yamlpass" "yamldb" "isolated" "false"
    
    local instance_file
    instance_file=$(get_instance_file "postgres" "yaml_test")
    
    # Test basic structure
    assert_success "grep -q '^engine:' '$instance_file'" "Should have engine field"
    assert_success "grep -q '^instance:' '$instance_file'" "Should have instance field"
    assert_success "grep -q '^version:' '$instance_file'" "Should have version field"
    assert_success "grep -q '^network:' '$instance_file'" "Should have network section"
    assert_success "grep -q '^db:' '$instance_file'" "Should have db section"
    assert_success "grep -q '^storage:' '$instance_file'" "Should have storage section"
    assert_success "grep -q '^state:' '$instance_file'" "Should have state section"
    
    # Test that passwords are stored (this is intentional for dblab)
    assert_success "grep -q 'password:' '$instance_file'" "Should store password in instance file"
}

# Run all tests
main() {
    run_test_suite "Instance Loader Tests" \
        test_get_container_name \
        test_get_network_name \
        test_get_instance_file \
        test_instance_exists \
        test_create_instance \
        test_load_instance \
        test_get_instance_config \
        test_update_instance_state \
        test_remove_instance \
        test_network_name_edge_cases \
        test_instance_validation \
        test_yaml_structure
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
