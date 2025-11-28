#!/usr/bin/env bash

# Test script for instance_writer.sh functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CORE_DIR="${PROJECT_DIR}/core"

# Source core utilities first (needed by instance_writer)
source "${CORE_DIR}/lib.sh"
source "${CORE_DIR}/yaml_parser.sh"
source "${CORE_DIR}/instance_writer.sh"

# Check if test_helper exists, if not create minimal testing functions
if [[ -f "${SCRIPT_DIR}/test_helper.sh" ]]; then
    source "${SCRIPT_DIR}/test_helper.sh"
else
    # Minimal test helper functions
    print_test_result() {
        local status=$1
        local message=$2
        if [[ "$status" == "PASS" ]]; then
            echo "✓ $message"
        else
            echo "✗ $message"
        fi
    }
fi

# Test directory setup
TEST_HOME="${TEST_HOME:-/tmp/dblab_test_$(date +%s)}"
export HOME="$TEST_HOME"
mkdir -p "$TEST_HOME"

# Cleanup function
cleanup() {
    rm -rf "$TEST_HOME"
}
trap cleanup EXIT

test_instance_file_exists() {
    echo "Testing instance_file_exists function..."
    
    # Test non-existent file
    if instance_file_exists "postgres" "test"; then
        echo "FAIL: instance_file_exists should return false for non-existent file"
        return 1
    fi
    
    # Create instance file
    local instance_file="$HOME/.local/share/dblab/postgres/test/instance.yml"
    mkdir -p "$(dirname "$instance_file")"
    echo "# test file" > "$instance_file"
    
    # Test existing file
    if ! instance_file_exists "postgres" "test"; then
        echo "FAIL: instance_file_exists should return true for existing file"
        return 1
    fi
    
    echo "PASS: instance_file_exists works correctly"
}

test_instance_writer_create_initial() {
    echo "Testing instance_writer_create_initial function..."
    
    # Setup test configuration
    declare -A TEST_CFG=(
        [engine]="postgres"
        [instance]="testdb"
        [version]="16"
        [image]="postgres:16"
        [db.user]="testuser"
        [db.password]="testpass"
        [db.database]="testdb"
        [db.port]="5432"
        [storage.persistent]="true"
        [storage.data_dir]="/test/data"
        [storage.config_dir]="/test/config"
        [network.mode]="isolated"
        [network.name]="dblab_postgres_testdb_net"
    )
    
    declare -a TEST_DB_FIELDS=(
        "db.user"
        "db.password" 
        "db.database"
        "db.port"
    )
    
    # Test initial creation
    if ! instance_writer_create_initial TEST_CFG TEST_DB_FIELDS; then
        echo "FAIL: instance_writer_create_initial failed"
        return 1
    fi
    
    # Verify file was created
    if ! instance_file_exists "postgres" "testdb"; then
        echo "FAIL: instance.yml was not created"
        return 1
    fi
    
    # Test idempotency (should not fail if called again)
    if ! instance_writer_create_initial TEST_CFG TEST_DB_FIELDS; then
        echo "FAIL: instance_writer_create_initial should be idempotent"
        return 1
    fi
    
    # Verify file content contains expected fields
    local instance_file="$HOME/.local/share/dblab/postgres/testdb/instance.yml"
    
    if ! grep -q "engine.*postgres" "$instance_file"; then
        echo "FAIL: instance.yml missing engine field"
        return 1
    fi
    
    if ! grep -q "instance.*testdb" "$instance_file"; then
        echo "FAIL: instance.yml missing instance field"
        return 1
    fi
    
    if ! grep -q "version.*16" "$instance_file"; then
        echo "FAIL: instance.yml missing version field"
        return 1
    fi
    
    echo "PASS: instance_writer_create_initial works correctly"
}

test_instance_writer_create_initial_validation() {
    echo "Testing instance_writer_create_initial validation..."
    
    # Test missing engine
    declare -A INVALID_CFG1=([instance]="test")
    declare -a EMPTY_DB_FIELDS=()
    
    if instance_writer_create_initial INVALID_CFG1 EMPTY_DB_FIELDS 2>/dev/null; then
        echo "FAIL: Should fail with missing engine"
        return 1
    fi
    
    # Test missing instance
    declare -A INVALID_CFG2=([engine]="postgres")
    
    if instance_writer_create_initial INVALID_CFG2 EMPTY_DB_FIELDS 2>/dev/null; then
        echo "FAIL: Should fail with missing instance"
        return 1
    fi
    
    echo "PASS: instance_writer_create_initial validation works correctly"
}

# Run tests
echo "=== Test Suite: Instance Writer Tests ==="
echo ""
echo "Test environment: $TEST_HOME"

# Initialize counters for summary
passed_tests=0
failed_tests=0
total_tests=0

run_test() {
    local test_name="$1"
    local test_func="$2"
    
    echo "Running: $test_name"
    total_tests=$((total_tests + 1))
    
    if $test_func; then
        passed_tests=$((passed_tests + 1))
        echo "✓ PASS: $test_name"
    else
        failed_tests=$((failed_tests + 1))
        echo "✗ FAIL: $test_name"
    fi
    echo ""
}

run_test "test_instance_file_exists" test_instance_file_exists
run_test "test_instance_writer_create_initial" test_instance_writer_create_initial
run_test "test_instance_writer_create_initial_validation" test_instance_writer_create_initial_validation

echo "=== Test Summary ==="
echo "Passed: $passed_tests"
echo "Failed: $failed_tests"
echo "Total:  $total_tests"

if [[ $failed_tests -gt 0 ]]; then
    echo "Some tests failed:"
    echo "Tests passed: $passed_tests/$total_tests"
    exit 1
else
    echo "All tests passed!"
    echo "Tests passed: $passed_tests/$total_tests"
    exit 0
fi
