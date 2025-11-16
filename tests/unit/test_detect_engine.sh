#!/bin/bash

# tests/unit/test_detect_engine.sh - Unit tests for core/detect_engine.sh
# Tests runtime detection and engine validation

set -euo pipefail

# Source test framework and modules under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helper.sh"
source "${SCRIPT_DIR}/../../core/lib.sh"
source "${SCRIPT_DIR}/../../core/detect_engine.sh"

# Test engine_exists function
test_engine_exists() {
    # Create test engine directory structure
    local test_engines_dir="$TEST_TMP_DIR/engines"
    mkdir -p "$test_engines_dir/postgres"
    
    # Create required files
    echo "engine: postgres" > "$test_engines_dir/postgres/metadata.yml"
    echo "#!/bin/bash" > "$test_engines_dir/postgres/main.sh"
    
    # Change to test directory to make engines/ relative path work
    pushd "$TEST_TMP_DIR" >/dev/null
    
    # Should find existing engine
    assert_success "engine_exists 'postgres'" "Should find postgres engine"
    
    # Should not find non-existent engine
    assert_failure "engine_exists 'mysql'" "Should not find non-existent engine"
    
    # Should fail if metadata.yml is missing
    rm "$test_engines_dir/postgres/metadata.yml"
    assert_failure "engine_exists 'postgres'" "Should fail if metadata.yml is missing"
    
    popd >/dev/null
}

# Test validate_engine function
test_validate_engine() {
    # Create test engine
    local test_engines_dir="$TEST_TMP_DIR/engines"
    mkdir -p "$test_engines_dir/testengine"
    echo "engine: testengine" > "$test_engines_dir/testengine/metadata.yml"
    echo "#!/bin/bash" > "$test_engines_dir/testengine/main.sh"
    
    pushd "$TEST_TMP_DIR" >/dev/null
    
    # Should validate existing engine
    assert_success "validate_engine 'testengine'" "Should validate existing engine"
    
    # Should fail for non-existent engine
    assert_failure "validate_engine 'nonexistent'" "Should fail for non-existent engine"
    
    popd >/dev/null
}

# Test list_engines function
test_list_engines() {
    # Create multiple test engines
    local test_engines_dir="$TEST_TMP_DIR/engines"
    mkdir -p "$test_engines_dir/postgres" "$test_engines_dir/mysql" "$test_engines_dir/incomplete"
    
    # Complete engines
    echo "engine: postgres" > "$test_engines_dir/postgres/metadata.yml"
    echo "#!/bin/bash" > "$test_engines_dir/postgres/main.sh"
    
    echo "engine: mysql" > "$test_engines_dir/mysql/metadata.yml"
    echo "#!/bin/bash" > "$test_engines_dir/mysql/main.sh"
    
    # Incomplete engine (missing main.sh)
    echo "engine: incomplete" > "$test_engines_dir/incomplete/metadata.yml"
    
    pushd "$TEST_TMP_DIR" >/dev/null
    
    # Capture output and test
    local output
    output=$(list_engines 2>&1)
    
    assert_contains "$output" "postgres" "Should list postgres engine"
    assert_contains "$output" "mysql" "Should list mysql engine"
    # Note: incomplete engine might or might not appear depending on implementation
    
    popd >/dev/null
}

# Test detect_runtimes function (mock version)
test_detect_runtimes_mock() {
    # Mock command_exists to simulate different scenarios
    
    # Test when both podman and docker exist
    mock_command_success "command_exists"
    local runtimes
    runtimes=$(detect_runtimes)
    assert_contains "$runtimes" "podman" "Should detect podman when available"
    assert_contains "$runtimes" "docker" "Should detect docker when available"
    
    # Test when no container runtime exists
    mock_command_failure "command_exists"
    assert_failure "detect_runtimes >/dev/null 2>&1" "Should fail when no runtimes available"
}

# Test get_container_runtime function (mock version)
test_get_container_runtime_mock() {
    # Mock detect_runtimes to return specific results
    mock_command_output "detect_runtimes" "podman docker"
    
    # Without CONTAINER_BACKEND set, should prefer podman
    unset CONTAINER_BACKEND || true
    local runtime
    runtime=$(get_container_runtime)
    assert_equals "$runtime" "podman" "Should prefer podman when both available"
    
    # With CONTAINER_BACKEND set to docker
    export CONTAINER_BACKEND="docker"
    runtime=$(get_container_runtime)
    assert_equals "$runtime" "docker" "Should use explicitly set backend"
    
    # With invalid CONTAINER_BACKEND
    export CONTAINER_BACKEND="invalid"
    assert_failure "get_container_runtime >/dev/null 2>&1" "Should fail with invalid backend"
    
    unset CONTAINER_BACKEND || true
}

# Test runtime capability checking (basic interface test)
test_runtime_capabilities_interface() {
    # These tests verify the interface exists and handles basic cases
    # We can't test actual runtime capabilities without docker/podman
    
    # Should handle unknown runtime gracefully
    assert_failure "check_runtime_capabilities 'nonexistent_runtime' >/dev/null 2>&1" "Should handle unknown runtime"
    
    # Test get_runtime_capability with no capabilities set
    local capability
    capability=$(get_runtime_capability "basic")
    assert_equals "$capability" "unknown" "Should return unknown for unset capability"
}

# Test is_rootless function (interface)
test_is_rootless_interface() {
    # Test with known runtime names (will fail without actual runtime, but tests interface)
    assert_failure "is_rootless 'docker'" "Should handle docker rootless check"
    assert_failure "is_rootless 'podman'" "Should handle podman rootless check"
    assert_failure "is_rootless 'unknown'" "Should handle unknown runtime"
}

# Test get_runtime_version function (mock)
test_get_runtime_version_mock() {
    # Mock runtime version commands
    local original_path="$PATH"
    
    # Create mock docker command
    local mock_bin="$TEST_TMP_DIR/bin"
    mkdir -p "$mock_bin"
    
    cat > "$mock_bin/docker" << 'EOF'
#!/bin/bash
echo "Docker version 24.0.7, build afdd53b"
EOF
    chmod +x "$mock_bin/docker"
    
    cat > "$mock_bin/podman" << 'EOF'
#!/bin/bash
echo "podman version 4.6.1"
EOF
    chmod +x "$mock_bin/podman"
    
    export PATH="$mock_bin:$PATH"
    
    # Test version extraction
    local docker_version
    docker_version=$(get_runtime_version "docker")
    assert_contains "$docker_version" "24.0.7" "Should extract docker version"
    
    local podman_version
    podman_version=$(get_runtime_version "podman")
    assert_contains "$podman_version" "4.6.1" "Should extract podman version"
    
    local unknown_version
    unknown_version=$(get_runtime_version "unknown")
    assert_equals "$unknown_version" "unknown" "Should return unknown for unknown runtime"
    
    # Restore PATH
    export PATH="$original_path"
}

# Run all tests
main() {
    run_test_suite "Runtime Detection Tests" \
        test_engine_exists \
        test_validate_engine \
        test_list_engines \
        test_detect_runtimes_mock \
        test_get_container_runtime_mock \
        test_runtime_capabilities_interface \
        test_is_rootless_interface \
        test_get_runtime_version_mock
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
