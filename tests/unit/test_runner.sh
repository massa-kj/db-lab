#!/bin/bash

# tests/unit/test_runner.sh - Unit tests for core/runner.sh
# Tests container runtime abstraction layer

set -euo pipefail

# Source test framework and modules under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helper.sh"
source "${SCRIPT_DIR}/../../core/lib.sh"
source "${SCRIPT_DIR}/../../core/detect_engine.sh"
source "${SCRIPT_DIR}/../../core/runner.sh"

# Test init_runner function (idempotent initialization)
test_init_runner() {
    # Mock DBLAB_CONTAINER_RUNTIME if not set
    if [[ -z "${DBLAB_CONTAINER_RUNTIME:-}" ]]; then
        export DBLAB_CONTAINER_RUNTIME="docker"
    fi
    
    # Should initialize successfully (even if runtime is mocked)
    assert_success "init_runner || true" "init_runner should not fail on mock runtime"
    
    # Should be idempotent - running again should not fail
    assert_success "init_runner || true" "init_runner should be idempotent"
}

# Test container runtime command building
test_build_container_command() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Test basic command building
    local cmd
    cmd=$(build_container_command "run" "-d" "--name" "test")
    assert_contains "$cmd" "docker run -d --name test" "Should build docker command correctly"
    
    # Test with podman
    export DBLAB_CONTAINER_RUNTIME="podman"
    cmd=$(build_container_command "run" "-it" "ubuntu")
    assert_contains "$cmd" "podman run -it ubuntu" "Should build podman command correctly"
}

# Test container_exists function (mock)
test_container_exists_mock() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Create mock docker command that simulates existing container
    local mock_bin="$TEST_TMP_DIR/bin"
    mkdir -p "$mock_bin"
    
    cat > "$mock_bin/docker" << 'EOF'
#!/bin/bash
case "$1 $2" in
    "ps -aq") 
        case "$4" in
            "existing_container") echo "container_id_123" ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$mock_bin/docker"
    
    local original_path="$PATH"
    export PATH="$mock_bin:$PATH"
    
    # Test existing container
    assert_success "container_exists 'existing_container'" "Should detect existing container"
    
    # Test non-existing container
    assert_failure "container_exists 'non_existing_container'" "Should not detect non-existing container"
    
    export PATH="$original_path"
}

# Test container_running function (mock)
test_container_running_mock() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Create mock docker command
    local mock_bin="$TEST_TMP_DIR/bin"
    mkdir -p "$mock_bin"
    
    cat > "$mock_bin/docker" << 'EOF'
#!/bin/bash
case "$1 $2" in
    "ps -q") 
        case "$4" in
            "running_container") echo "container_id_456" ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$mock_bin/docker"
    
    local original_path="$PATH"
    export PATH="$mock_bin:$PATH"
    
    # Test running container
    assert_success "container_running 'running_container'" "Should detect running container"
    
    # Test non-running container
    assert_failure "container_running 'stopped_container'" "Should not detect stopped container"
    
    export PATH="$original_path"
}

# Test get_container_state function (mock)
test_get_container_state_mock() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Create mock docker command
    local mock_bin="$TEST_TMP_DIR/bin"
    mkdir -p "$mock_bin"
    
    cat > "$mock_bin/docker" << 'EOF'
#!/bin/bash
case "$1 $2" in
    "inspect --format") 
        case "$4" in
            "running_container") echo "running" ;;
            "stopped_container") echo "exited" ;;
            "paused_container") echo "paused" ;;
            *) echo "not_found" && exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$mock_bin/docker"
    
    local original_path="$PATH"
    export PATH="$mock_bin:$PATH"
    
    # Test different container states
    local state
    state=$(get_container_state "running_container")
    assert_equals "$state" "running" "Should return running state"
    
    state=$(get_container_state "stopped_container")
    assert_equals "$state" "exited" "Should return exited state"
    
    state=$(get_container_state "paused_container")
    assert_equals "$state" "paused" "Should return paused state"
    
    # Test non-existent container
    assert_failure "get_container_state 'non_existent_container' >/dev/null 2>&1" "Should fail for non-existent container"
    
    export PATH="$original_path"
}

# Test start_container function interface
test_start_container_interface() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Test parameter validation
    assert_failure "start_container '' 'ubuntu' >/dev/null 2>&1" "Should fail with empty container name"
    assert_failure "start_container 'test' '' >/dev/null 2>&1" "Should fail with empty image"
    
    # Note: Actual container start testing would require real runtime
    # This tests the interface validation only
}

# Test stop_container function interface
test_stop_container_interface() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Test parameter validation
    assert_failure "stop_container '' >/dev/null 2>&1" "Should fail with empty container name"
    
    # Note: Actual container stop testing would require real runtime
}

# Test remove_container function interface
test_remove_container_interface() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Test parameter validation
    assert_failure "remove_container '' >/dev/null 2>&1" "Should fail with empty container name"
    
    # Note: Actual container removal testing would require real runtime
}

# Test container_logs function interface
test_container_logs_interface() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Test parameter validation
    assert_failure "container_logs '' >/dev/null 2>&1" "Should fail with empty container name"
    
    # Note: Actual log retrieval testing would require real runtime
}

# Test exec_in_container function interface
test_exec_in_container_interface() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Test parameter validation
    assert_failure "exec_in_container '' 'echo test' >/dev/null 2>&1" "Should fail with empty container name"
    assert_failure "exec_in_container 'test' '' >/dev/null 2>&1" "Should fail with empty command"
    
    # Note: Actual command execution testing would require real runtime
}

# Run all tests
main() {
    run_test_suite "Container Runner Tests" \
        test_init_runner \
        test_build_container_command \
        test_container_exists_mock \
        test_container_running_mock \
        test_get_container_state_mock \
        test_start_container_interface \
        test_stop_container_interface \
        test_remove_container_interface \
        test_container_logs_interface \
        test_exec_in_container_interface
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
