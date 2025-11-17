#!/bin/bash

# tests/unit/run_all_tests.sh - Run all unit tests for core modules
# Test runner for the complete dblab core test suite

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test configuration
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_SUITES=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Print test suite header
print_suite_header() {
    local suite_name=$1
    print_color "$BLUE" "\n==================== $suite_name ===================="
}

# Print test suite result
print_suite_result() {
    local suite_name=$1
    local suite_passed=$2
    local suite_total=$3
    
    if [[ $suite_passed -eq $suite_total ]]; then
        print_color "$GREEN" "✓ $suite_name: $suite_passed/$suite_total tests passed"
    else
        local suite_failed=$((suite_total - suite_passed))
        print_color "$RED" "✗ $suite_name: $suite_passed/$suite_total tests passed ($suite_failed failed)"
        FAILED_SUITES+=("$suite_name")
    fi
}

# Run a single test suite
run_test_suite() {
    local test_script=$1
    local suite_name=$2
    
    print_suite_header "$suite_name"
    
    if [[ ! -f "$test_script" ]]; then
        print_color "$RED" "✗ Test script not found: $test_script"
        FAILED_SUITES+=("$suite_name")
        return 1
    fi
    
    # Make script executable
    chmod +x "$test_script"
    
    # Capture test output
    local output
    local exit_code=0
    
    # Run the test script and capture its output
    if output=$("$test_script" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Parse test results from output
    local suite_passed=0
    local suite_total=0
    
    # Count passed and total tests from output
    if [[ $output =~ Tests\ passed:\ ([0-9]+)/([0-9]+) ]]; then
        suite_passed="${BASH_REMATCH[1]}"
        suite_total="${BASH_REMATCH[2]}"
    else
        # Fallback: count by looking at test output patterns
        suite_passed=$(echo "$output" | grep -c "✓" || true)
        local failed=$(echo "$output" | grep -c "✗" || true)
        
        # Ensure we have valid numbers
        [[ -z "$suite_passed" || "$suite_passed" == "" ]] && suite_passed=0
        [[ -z "$failed" || "$failed" == "" ]] && failed=0
        
        suite_total=$((suite_passed + failed))
    fi
    
    # Update global counters
    TOTAL_TESTS=$((TOTAL_TESTS + suite_total))
    PASSED_TESTS=$((PASSED_TESTS + suite_passed))
    FAILED_TESTS=$((FAILED_TESTS + suite_total - suite_passed))
    
    # Show detailed output if there are failures
    if [[ $exit_code -ne 0 ]] || [[ $suite_passed -ne $suite_total ]]; then
        echo "$output"
    fi
    
    print_suite_result "$suite_name" "$suite_passed" "$suite_total"
    
    return $exit_code
}

# Main test execution
main() {
    print_color "$BLUE" "Starting dblab core modules unit test suite..."
    print_color "$BLUE" "================================================"
    
    local start_time=$(date +%s)
    
    # Define test suites to run
    local test_suites=(
        "${SCRIPT_DIR}/test_lib.sh|Core Utilities (lib.sh)"
        "${SCRIPT_DIR}/test_env_loader.sh|Environment Loader"
        "${SCRIPT_DIR}/test_instance_loader.sh|Instance Management"
        "${SCRIPT_DIR}/test_detect_engine.sh|Runtime Detection"
        "${SCRIPT_DIR}/test_runner.sh|Container Runner"
        "${SCRIPT_DIR}/test_network.sh|Network Management"
        "${SCRIPT_DIR}/test_yaml_parser.sh|YAML Parser"
    )
    
    # Run each test suite
    for suite_def in "${test_suites[@]}"; do
        IFS='|' read -r script_path suite_name <<< "$suite_def"
        
        # Skip if test doesn't exist
        if [[ ! -f "$script_path" ]]; then
            print_color "$YELLOW" "⚠ Skipping $suite_name (test file not found)"
            continue
        fi
        
        run_test_suite "$script_path" "$suite_name" || true
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Print final summary
    print_color "$BLUE" "\n==================== TEST SUMMARY ===================="
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        print_color "$GREEN" "🎉 ALL TESTS PASSED!"
        print_color "$GREEN" "✓ $PASSED_TESTS/$TOTAL_TESTS tests passed"
    else
        print_color "$RED" "❌ SOME TESTS FAILED"
        print_color "$RED" "✗ $FAILED_TESTS/$TOTAL_TESTS tests failed"
        
        if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
            print_color "$RED" "\nFailed test suites:"
            for failed_suite in "${FAILED_SUITES[@]}"; do
                print_color "$RED" "  - $failed_suite"
            done
        fi
    fi
    
    print_color "$BLUE" "\nExecution time: ${duration}s"
    print_color "$BLUE" "Test results: $PASSED_TESTS passed, $FAILED_TESTS failed, $TOTAL_TESTS total"
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Handle command line options
case "${1:-}" in
    --help|-h)
        cat << EOF
Usage: $0 [OPTIONS]

Run all unit tests for dblab core modules.

OPTIONS:
    --help, -h     Show this help message
    --verbose, -v  Show verbose output (currently default)
    --quiet, -q    Show only summary (not implemented)

EXAMPLES:
    $0                 # Run all tests
    $0 --help          # Show help

EXIT CODES:
    0  All tests passed
    1  One or more tests failed
EOF
        exit 0
        ;;
    --verbose|-v)
        # Verbose is default behavior
        main
        ;;
    --quiet|-q)
        # TODO: Implement quiet mode
        print_color "$YELLOW" "Quiet mode not yet implemented. Running in verbose mode."
        main
        ;;
    "")
        main
        ;;
    *)
        print_color "$RED" "Unknown option: $1"
        print_color "$RED" "Use --help for usage information."
        exit 1
        ;;
esac
