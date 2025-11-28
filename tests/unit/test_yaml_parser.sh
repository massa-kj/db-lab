#!/bin/bash

# tests/unit/test_yaml_parser.sh - Unit tests for core/yaml_parser.sh
# Tests the basic YAML parsing functionality used by metadata validation

set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source test framework and module under test
source "${SCRIPT_DIR}/test_helper.sh"
source "${PROJECT_ROOT}/core/yaml_parser.sh"

# Test data directory
TEST_YAML_DIR=""

setup_yaml_test_env() {
    setup_test_env
    TEST_YAML_DIR="$TEST_TMP_DIR/yaml"
    mkdir -p "$TEST_YAML_DIR"
    create_test_yaml_files
}

# Create test YAML files
create_test_yaml_files() {
    # Simple valid YAML
    cat > "$TEST_YAML_DIR/simple.yml" << 'EOF'
engine: postgres
version:
  default: "16"
  supported:
    - "16"
    - "15"
    - "14"

required_env:
  - DBLAB_PG_VERSION
  - DBLAB_PG_USER
  - DBLAB_PG_PASSWORD

defaults:
  DBLAB_PG_VERSION: "16"
  DBLAB_PG_USER: "postgres"
  DBLAB_PG_DATABASE: "app"
  DBLAB_PG_PORT: "5432"

validation:
  user_regex: "^[a-zA-Z0-9_]+$"
  dbname_regex: "^[a-zA-Z0-9_]+$"
  password_min_length: 8
EOF

    # YAML with quotes and special characters
    cat > "$TEST_YAML_DIR/quotes.yml" << 'EOF'
engine: "sqlserver"
defaults:
  DBLAB_SQLSERVER_VERSION: "2022-latest"
  DBLAB_SQLSERVER_SA_PASSWORD: "MyPass123!"
  DBLAB_SQLSERVER_DATABASE: "app"
  DBLAB_SQLSERVER_PORT: "1433"
  DBLAB_EPHEMERAL: false
EOF

    # Empty/minimal YAML
    cat > "$TEST_YAML_DIR/minimal.yml" << 'EOF'
engine: redis
required_env: []
defaults: {}
EOF

    # Invalid YAML
    cat > "$TEST_YAML_DIR/invalid.yml" << 'EOF'
engine: broken
  invalid_indentation
missing_colon
  - malformed_array
EOF
}

# Test parse_yaml_array function
test_parse_yaml_array() {
    setup_yaml_test_env
    
    local result expected
    result=$(parse_yaml_array "$TEST_YAML_DIR/simple.yml" "required_env")
    expected="DBLAB_PG_VERSION
DBLAB_PG_USER
DBLAB_PG_PASSWORD"
    assert_equals "$expected" "$result" "Should parse required_env array correctly"
    
    # Test supported versions array
    result=$(parse_yaml_array "$TEST_YAML_DIR/simple.yml" "supported")
    expected="16
15
14"
    assert_equals "$expected" "$result" "Should parse nested supported array correctly"
    
    # Test empty array
    result=$(parse_yaml_array "$TEST_YAML_DIR/minimal.yml" "required_env")
    assert_equals "" "$result" "Should handle empty array"
}

# Test parse_yaml_section function
test_parse_yaml_section() {
    setup_yaml_test_env
    
    local result
    result=$(parse_yaml_section "$TEST_YAML_DIR/simple.yml" "defaults")
    
    # Check if key=value pairs are present (each on separate lines)
    assert_contains "$result" "DBLAB_PG_VERSION=16" "Should contain version default"
    assert_contains "$result" "DBLAB_PG_USER=postgres" "Should contain user default"
    assert_contains "$result" "DBLAB_PG_DATABASE=app" "Should contain database default"
    assert_contains "$result" "DBLAB_PG_PORT=5432" "Should contain port default"
    
    # Test validation section
    result=$(parse_yaml_section "$TEST_YAML_DIR/simple.yml" "validation")
    assert_contains "$result" "user_regex=^[a-zA-Z0-9_]+$" "Should contain user regex"
    assert_contains "$result" "password_min_length=8" "Should contain password min length"
}

# Report test results
report_test_results() {
    echo "============================="
    echo "YAML Parser Test Results:"
    echo "Passed: ${#TESTS_PASSED[@]}"
    echo "Failed: ${#TESTS_FAILED[@]}"
    echo "Total:  $((${#TESTS_PASSED[@]} + ${#TESTS_FAILED[@]}))"
    
    if [[ ${#TESTS_FAILED[@]} -eq 0 ]]; then
        echo "All tests passed! ✓"
        return 0
    else
        echo "Some tests failed:"
        for failed_test in "${TESTS_FAILED[@]}"; do
            echo "  - $failed_test"
        done
        return 1
    fi
}

# Main test execution
main() {
    echo "Running YAML Parser Tests..."
    echo "============================="
    
    # Run test functions using the framework
    run_test "test_parse_yaml_array" 
    run_test "test_parse_yaml_section"
    
    # Report results
    report_test_results
}

# Run tests if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
