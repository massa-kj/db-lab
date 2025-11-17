#!/bin/bash

# tests/unit/test_network.sh - Unit tests for core/network.sh
# Tests network management functionality

set -euo pipefail

# Source test framework and modules under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_helper.sh"
source "${SCRIPT_DIR}/../../core/lib.sh"
source "${SCRIPT_DIR}/../../core/detect_engine.sh"
source "${SCRIPT_DIR}/../../core/runner.sh"
source "${SCRIPT_DIR}/../../core/network.sh"

# Test generate_network_name function
test_generate_network_name() {
    # Test normal case
    local network_name
    network_name=$(generate_network_name "postgres" "myapp")
    assert_equals "$network_name" "dblab-postgres-myapp" "Should generate correct network name"
    
    # Test with special characters (should be sanitized)
    network_name=$(generate_network_name "postgres" "my_app-test")
    assert_equals "$network_name" "dblab-postgres-my_app-test" "Should handle special characters"
}

# Test network_exists function (mock)
test_network_exists_mock() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Create mock docker command
    local mock_bin="$TEST_TMP_DIR/bin"
    mkdir -p "$mock_bin"
    
    cat > "$mock_bin/docker" << 'EOF'
#!/bin/bash
case "$1 $2" in
    "network ls") 
        case "$*" in
            *"existing-network"*) echo "network_id existing-network bridge local" ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$mock_bin/docker"
    
    local original_path="$PATH"
    export PATH="$mock_bin:$PATH"
    
    # Test existing network
    assert_success "network_exists 'existing-network'" "Should detect existing network"
    
    # Test non-existing network
    assert_failure "network_exists 'non-existing-network'" "Should not detect non-existing network"
    
    export PATH="$original_path"
}

# Test create_network function interface
test_create_network_interface() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Test parameter validation
    assert_failure "create_network '' >/dev/null 2>&1" "Should fail with empty network name"
    
    # Note: Actual network creation testing would require real runtime
}

# Test remove_network function interface
test_remove_network_interface() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Test parameter validation
    assert_failure "remove_network '' >/dev/null 2>&1" "Should fail with empty network name"
    
    # Note: Actual network removal testing would require real runtime
}

# Test ensure_network function (mock)
test_ensure_network_mock() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Create mock docker command that simulates network creation
    local mock_bin="$TEST_TMP_DIR/bin"
    mkdir -p "$mock_bin"
    
    cat > "$mock_bin/docker" << 'EOF'
#!/bin/bash
case "$1" in
    "network")
        case "$2" in
            "ls")
                # First call - network doesn't exist
                if [[ ! -f "/tmp/network_created" ]]; then
                    exit 1
                else
                    echo "network_id test-network bridge local"
                fi
                ;;
            "create")
                # Mark network as created
                touch "/tmp/network_created"
                echo "Created network: test-network"
                ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$mock_bin/docker"
    
    local original_path="$PATH"
    export PATH="$mock_bin:$PATH"
    
    # Clean up any previous state
    rm -f "/tmp/network_created"
    
    # Should create network if it doesn't exist
    assert_success "ensure_network 'test-network'" "Should create network if not exists"
    
    # Should succeed if network already exists
    assert_success "ensure_network 'test-network'" "Should succeed if network already exists"
    
    # Clean up
    rm -f "/tmp/network_created"
    export PATH="$original_path"
}

# Test get_network_info function (mock)
test_get_network_info_mock() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Create mock docker command
    local mock_bin="$TEST_TMP_DIR/bin"
    mkdir -p "$mock_bin"
    
    cat > "$mock_bin/docker" << 'EOF'
#!/bin/bash
case "$1 $2" in
    "network inspect") 
        case "$3" in
            "test-network") 
                cat << 'NETWORK_INFO'
[
    {
        "Name": "test-network",
        "Id": "abc123",
        "Driver": "bridge",
        "Scope": "local"
    }
]
NETWORK_INFO
                ;;
            *) echo "[]" ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$mock_bin/docker"
    
    local original_path="$PATH"
    export PATH="$mock_bin:$PATH"
    
    # Test getting network info
    local info
    info=$(get_network_info "test-network")
    assert_contains "$info" "test-network" "Should return network information"
    assert_contains "$info" "bridge" "Should include driver information"
    
    # Test non-existent network
    info=$(get_network_info "non-existent")
    assert_equals "$info" "[]" "Should return empty array for non-existent network"
    
    export PATH="$original_path"
}

# Test connect_container_to_network function interface
test_connect_container_to_network_interface() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Test parameter validation
    assert_failure "connect_container_to_network '' 'test-network' >/dev/null 2>&1" "Should fail with empty container name"
    assert_failure "connect_container_to_network 'test-container' '' >/dev/null 2>&1" "Should fail with empty network name"
    
    # Note: Actual connection testing would require real runtime
}

# Test disconnect_container_from_network function interface
test_disconnect_container_from_network_interface() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Test parameter validation
    assert_failure "disconnect_container_from_network '' 'test-network' >/dev/null 2>&1" "Should fail with empty container name"
    assert_failure "disconnect_container_from_network 'test-container' '' >/dev/null 2>&1" "Should fail with empty network name"
    
    # Note: Actual disconnection testing would require real runtime
}

# Test list_network_containers function (mock)
test_list_network_containers_mock() {
    export DBLAB_CONTAINER_RUNTIME="docker"
    
    # Create mock docker command
    local mock_bin="$TEST_TMP_DIR/bin"
    mkdir -p "$mock_bin"
    
    cat > "$mock_bin/docker" << 'EOF'
#!/bin/bash
case "$1 $2" in
    "network inspect") 
        case "$3" in
            "test-network") 
                cat << 'NETWORK_CONTAINERS'
[
    {
        "Name": "test-network",
        "Containers": {
            "container1": {
                "Name": "app1",
                "IPv4Address": "172.20.0.2/16"
            },
            "container2": {
                "Name": "app2",
                "IPv4Address": "172.20.0.3/16"
            }
        }
    }
]
NETWORK_CONTAINERS
                ;;
            *) echo "[]" ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$mock_bin/docker"
    
    local original_path="$PATH"
    export PATH="$mock_bin:$PATH"
    
    # Test listing containers in network
    local containers
    containers=$(list_network_containers "test-network")
    assert_contains "$containers" "app1" "Should list containers in network"
    assert_contains "$containers" "app2" "Should list all containers"
    
    # Test empty network
    containers=$(list_network_containers "empty-network")
    assert_equals "$containers" "" "Should return empty for non-existent network"
    
    export PATH="$original_path"
}

# Run all tests
main() {
    run_test_suite "Network Management Tests" \
        test_generate_network_name \
        test_network_exists_mock \
        test_create_network_interface \
        test_remove_network_interface \
        test_ensure_network_mock \
        test_get_network_info_mock \
        test_connect_container_to_network_interface \
        test_disconnect_container_from_network_interface \
        test_list_network_containers_mock
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
