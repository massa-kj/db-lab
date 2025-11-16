#!/bin/bash

# tests/unit/test_helper.sh - Unit testing framework for dblab core modules
# Provides minimal test utilities for bash functions

set -euo pipefail

# Test state
declare -a TESTS_PASSED=()
declare -a TESTS_FAILED=()
declare -g CURRENT_TEST_NAME=""

# Colors for output
readonly TEST_GREEN='\033[0;32m'
readonly TEST_RED='\033[0;31m'
readonly TEST_BLUE='\033[0;34m'
readonly TEST_NC='\033[0m' # No Color

# Test environment setup
setup_test_env() {
    # Create temporary directory for tests
    TEST_TMP_DIR=$(mktemp -d -t dblab-test.XXXXXX)
    export DBLAB_BASE_DIR="$TEST_TMP_DIR/data"
    export DBLAB_LOG_LEVEL="error"  # Reduce noise in tests
    
    # Create required directories
    mkdir -p "$DBLAB_BASE_DIR"
    
    echo "Test environment: $TEST_TMP_DIR"
}

# Test environment cleanup
cleanup_test_env() {
    if [[ -n "${TEST_TMP_DIR:-}" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

# Assert functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$expected" == "$actual" ]]; then
        test_pass "assert_equals: $message"
        return 0
    else
        test_fail "assert_equals: Expected '$expected', got '$actual'. $message"
        return 1
    fi
}

assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$expected" != "$actual" ]]; then
        test_pass "assert_not_equals: $message"
        return 0
    else
        test_fail "assert_not_equals: Expected not '$expected', but got '$actual'. $message"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        test_pass "assert_contains: $message"
        return 0
    else
        test_fail "assert_contains: '$needle' not found in '$haystack'. $message"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-}"
    
    if [[ -f "$file" ]]; then
        test_pass "assert_file_exists: $message"
        return 0
    else
        test_fail "assert_file_exists: File '$file' does not exist. $message"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-}"
    
    if [[ -d "$dir" ]]; then
        test_pass "assert_dir_exists: $message"
        return 0
    else
        test_fail "assert_dir_exists: Directory '$dir' does not exist. $message"
        return 1
    fi
}

assert_success() {
    local command="$1"
    local message="${2:-}"
    
    if eval "$command" >/dev/null 2>&1; then
        test_pass "assert_success: $message"
        return 0
    else
        test_fail "assert_success: Command '$command' failed. $message"
        return 1
    fi
}

assert_failure() {
    local command="$1"
    local message="${2:-}"
    
    if ! eval "$command" >/dev/null 2>&1; then
        test_pass "assert_failure: $message"
        return 0
    else
        test_fail "assert_failure: Command '$command' succeeded unexpectedly. $message"
        return 1
    fi
}

# Test execution functions
run_test() {
    local test_function="$1"
    CURRENT_TEST_NAME="$test_function"
    
    echo -e "${TEST_BLUE}Running: $test_function${TEST_NC}"
    
    # Run test in subshell to isolate environment changes
    if (set -e; "$test_function"); then
        TESTS_PASSED+=("$test_function")
        echo -e "${TEST_GREEN}✓ PASS: $test_function${TEST_NC}"
    else
        TESTS_FAILED+=("$test_function")
        echo -e "${TEST_RED}✗ FAIL: $test_function${TEST_NC}"
    fi
    
    echo ""
}

# Internal test result tracking
test_pass() {
    local message="$1"
    echo "    ✓ $message"
}

test_fail() {
    local message="$1"
    echo "    ✗ $message"
    return 1
}

# Test suite execution
run_test_suite() {
    local suite_name="$1"
    shift
    local test_functions=("$@")
    
    echo -e "${TEST_BLUE}=== Test Suite: $suite_name ===${TEST_NC}"
    echo ""
    
    setup_test_env
    
    # Set trap for cleanup
    trap cleanup_test_env EXIT
    
    # Run each test
    for test_func in "${test_functions[@]}"; do
        run_test "$test_func"
    done
    
    # Print summary
    echo -e "${TEST_BLUE}=== Test Summary ===${TEST_NC}"
    echo "Passed: ${#TESTS_PASSED[@]}"
    echo "Failed: ${#TESTS_FAILED[@]}"
    echo "Total:  $((${#TESTS_PASSED[@]} + ${#TESTS_FAILED[@]}))"
    
    if [[ ${#TESTS_FAILED[@]} -eq 0 ]]; then
        echo -e "${TEST_GREEN}All tests passed!${TEST_NC}"
        return 0
    else
        echo -e "${TEST_RED}Some tests failed:${TEST_NC}"
        for failed_test in "${TESTS_FAILED[@]}"; do
            echo -e "${TEST_RED}  - $failed_test${TEST_NC}"
        done
        return 1
    fi
}

# Mock functions for testing
mock_command_success() {
    local command="$1"
    eval "$command() { return 0; }"
}

mock_command_failure() {
    local command="$1"
    eval "$command() { return 1; }"
}

mock_command_output() {
    local command="$1"
    local output="$2"
    eval "$command() { echo '$output'; }"
}

# Export test utilities
export -f setup_test_env cleanup_test_env
export -f assert_equals assert_not_equals assert_contains
export -f assert_file_exists assert_dir_exists assert_success assert_failure
export -f run_test run_test_suite test_pass test_fail
export -f mock_command_success mock_command_failure mock_command_output
