#!/bin/bash

# DBLab Installation Script
# This script installs DBLab system-wide

set -euo pipefail

# Configuration
readonly DBLAB_INSTALL_DIR="/opt/dblab"
readonly DBLAB_BIN_LINK="/usr/local/bin/dblab"
readonly DBLAB_UNINSTALL_SCRIPT="/usr/local/bin/dblab-uninstall"
readonly DBLAB_VERSION_FILE="VERSION"
readonly DBLAB_USER_DATA_DIR="~/.local/share/dblab"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

die() {
    error "$*"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (use sudo)"
    fi
}

# Check system requirements
check_requirements() {
    info "Checking system requirements..."
    
    # Check OS
    if ! command -v uname >/dev/null 2>&1; then
        die "Cannot determine operating system"
    fi
    
    local os
    os=$(uname -s)
    case "$os" in
        Linux|Darwin)
            debug "OS supported: $os"
            ;;
        *)
            die "Unsupported operating system: $os"
            ;;
    esac
    
    # Check bash version
    if [[ -z "${BASH_VERSION:-}" ]]; then
        die "Bash is required"
    fi
    
    local bash_major_version
    bash_major_version="${BASH_VERSION%%.*}"
    if [[ "$bash_major_version" -lt 4 ]]; then
        die "Bash 4.0+ is required (current: $BASH_VERSION)"
    fi
    
    debug "Bash version supported: $BASH_VERSION"
    
    # Check for container runtime
    if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
        warn "Neither Docker nor Podman found"
        warn "Please install Docker or Podman before using DBLab"
    else
        debug "Container runtime available"
    fi
    
    info "System requirements check passed"
}

# Detect installation source
detect_source() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Check if we're in the project directory
    if [[ -f "${script_dir}/${DBLAB_VERSION_FILE}" && -d "${script_dir}/bin" && -d "${script_dir}/core" ]]; then
        INSTALL_SOURCE="local"
        INSTALL_SOURCE_PATH="$script_dir"
        debug "Installation source: local ($script_dir)"
    else
        die "Cannot detect DBLab source. Please run this script from the DBLab project directory."
    fi
}

# Get DBLab version
get_version() {
    if [[ -f "${INSTALL_SOURCE_PATH}/${DBLAB_VERSION_FILE}" ]]; then
        DBLAB_VERSION=$(cat "${INSTALL_SOURCE_PATH}/${DBLAB_VERSION_FILE}")
    else
        DBLAB_VERSION="unknown"
    fi
    debug "DBLab version: $DBLAB_VERSION"
}

# Remove existing installation
remove_existing() {
    if [[ -d "$DBLAB_INSTALL_DIR" ]]; then
        warn "Removing existing installation at $DBLAB_INSTALL_DIR"
        rm -rf "$DBLAB_INSTALL_DIR"
    fi
    
    if [[ -L "$DBLAB_BIN_LINK" ]]; then
        warn "Removing existing symlink at $DBLAB_BIN_LINK"
        rm -f "$DBLAB_BIN_LINK"
    fi
    
    if [[ -f "$DBLAB_UNINSTALL_SCRIPT" ]]; then
        warn "Removing existing uninstall script"
        rm -f "$DBLAB_UNINSTALL_SCRIPT"
    fi
}

# Copy files to installation directory
install_files() {
    info "Installing DBLab to $DBLAB_INSTALL_DIR..."
    
    # Create installation directory
    mkdir -p "$DBLAB_INSTALL_DIR"
    
    # Copy essential directories
    local dirs_to_copy=("bin" "core" "engines" "templates")
    
    for dir in "${dirs_to_copy[@]}"; do
        if [[ -d "${INSTALL_SOURCE_PATH}/${dir}" ]]; then
            debug "Copying $dir..."
            cp -r "${INSTALL_SOURCE_PATH}/${dir}" "$DBLAB_INSTALL_DIR/"
        else
            die "Required directory not found: $dir"
        fi
    done
    
    # Copy essential files
    local files_to_copy=("VERSION" "README.md")
    
    for file in "${files_to_copy[@]}"; do
        if [[ -f "${INSTALL_SOURCE_PATH}/${file}" ]]; then
            debug "Copying $file..."
            cp "${INSTALL_SOURCE_PATH}/${file}" "$DBLAB_INSTALL_DIR/"
        fi
    done
    
    # Set permissions
    chmod +x "${DBLAB_INSTALL_DIR}/bin/dblab"
    find "${DBLAB_INSTALL_DIR}/engines" -name "*.sh" -exec chmod +x {} \;
    find "${DBLAB_INSTALL_DIR}/core" -name "*.sh" -exec chmod +x {} \;
    
    # Set ownership to current user for runtime flexibility (optional)
    # Uncomment if you want non-root users to modify installed files
    # chown -R "$(logname):$(id -gn "$(logname)")" "${DBLAB_INSTALL_DIR}" 2>/dev/null || true
    
    info "Files installed successfully"
}

# Create symlink
create_symlink() {
    info "Creating symlink..."
    
    # Create symlink to main binary
    ln -sf "${DBLAB_INSTALL_DIR}/bin/dblab" "$DBLAB_BIN_LINK"
    
    # Verify symlink
    if [[ -L "$DBLAB_BIN_LINK" && -x "$DBLAB_BIN_LINK" ]]; then
        debug "Symlink created successfully"
    else
        die "Failed to create working symlink"
    fi
}

# Create uninstall script
create_uninstall_script() {
    info "Creating uninstall script..."
    
    cat > "$DBLAB_UNINSTALL_SCRIPT" << 'EOF'
#!/bin/bash

# DBLab Uninstall Script
# This script removes DBLab from the system

set -euo pipefail

# Configuration
readonly DBLAB_INSTALL_DIR="/opt/dblab"
readonly DBLAB_BIN_LINK="/usr/local/bin/dblab"
readonly DBLAB_UNINSTALL_SCRIPT="/usr/local/bin/dblab-uninstall"
readonly DBLAB_USER_DATA_DIR="$HOME/.local/share/dblab"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Command line options
REMOVE_USER_DATA="false"
STOP_CONTAINERS="false"
FORCE_MODE="false"

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

die() {
    error "$*"
    exit 1
}

# Show help message
show_help() {
    cat << HELP_EOF
DBLab Uninstall Script

USAGE:
    sudo dblab-uninstall [options]

OPTIONS:
    --remove-data       Remove user data directory (~/.local/share/dblab)
    --stop-containers   Stop all running DBLab containers before uninstall
    --force            Skip all confirmation prompts
    --help, -h         Show this help message

EXAMPLES:
    # Standard uninstall (keeps user data and containers)
    sudo dblab-uninstall
    
    # Uninstall and remove all user data
    sudo dblab-uninstall --remove-data
    
    # Force uninstall with data removal (no prompts)
    sudo dblab-uninstall --remove-data --force

NOTES:
    - This script must be run as root (use sudo)
    - By default, user data and containers are preserved
    - User data includes instance configurations and database volumes
    - Use --remove-data to permanently delete all DBLab data
HELP_EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --remove-data)
                REMOVE_USER_DATA="true"
                shift
                ;;
            --stop-containers)
                STOP_CONTAINERS="true"
                shift
                ;;
            --force)
                FORCE_MODE="true"
                shift
                ;;
            *)
                die "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (use sudo)"
    fi
}

# Get the original user (who invoked sudo)
get_original_user() {
    local original_user="${SUDO_USER:-$USER}"
    if [[ "$original_user" == "root" ]]; then
        # Try to get user from environment
        original_user="${LOGNAME:-}"
        if [[ -z "$original_user" || "$original_user" == "root" ]]; then
            warn "Cannot determine original user, assuming 'root'"
            original_user="root"
        fi
    fi
    echo "$original_user"
}

# Stop DBLab containers
stop_dblab_containers() {
    local original_user
    original_user=$(get_original_user)
    
    info "Stopping DBLab containers..."
    
    # Check for docker
    if command -v docker >/dev/null 2>&1; then
        local containers
        containers=$(docker ps --filter "name=dblab_" --format "{{.Names}}" 2>/dev/null || true)
        
        if [[ -n "$containers" ]]; then
            info "Found running DBLab containers:"
            echo "$containers"
            
            if [[ "$FORCE_MODE" != "true" ]]; then
                read -p "Stop these containers? (y/n): " -r response
                case "$response" in
                    y|Y|yes|YES)
                        ;;
                    *)
                        info "Skipping container stop"
                        return 0
                        ;;
                esac
            fi
            
            echo "$containers" | xargs -r docker stop
            info "Containers stopped"
        else
            debug "No running DBLab containers found"
        fi
    fi
    
    # Check for podman
    if command -v podman >/dev/null 2>&1; then
        local containers
        # Try to run as original user if possible
        if [[ "$original_user" != "root" ]]; then
            containers=$(su - "$original_user" -c 'podman ps --filter "name=dblab_" --format "{{.Names}}" 2>/dev/null || true' || true)
        else
            containers=$(podman ps --filter "name=dblab_" --format "{{.Names}}" 2>/dev/null || true)
        fi
        
        if [[ -n "$containers" ]]; then
            info "Found running DBLab containers (podman):"
            echo "$containers"
            
            if [[ "$FORCE_MODE" != "true" ]]; then
                read -p "Stop these containers? (y/n): " -r response
                case "$response" in
                    y|Y|yes|YES)
                        ;;
                    *)
                        info "Skipping container stop"
                        return 0
                        ;;
                esac
            fi
            
            if [[ "$original_user" != "root" ]]; then
                su - "$original_user" -c "echo '$containers' | xargs -r podman stop" || true
            else
                echo "$containers" | xargs -r podman stop
            fi
            info "Containers stopped"
        else
            debug "No running DBLab containers found (podman)"
        fi
    fi
}

# Remove user data
remove_user_data() {
    local original_user
    original_user=$(get_original_user)
    local user_data_dir
    
    # Construct user data directory path
    if [[ "$original_user" != "root" ]]; then
        user_data_dir="/home/$original_user/.local/share/dblab"
    else
        user_data_dir="/root/.local/share/dblab"
    fi
    
    if [[ ! -d "$user_data_dir" ]]; then
        debug "User data directory not found: $user_data_dir"
        return 0
    fi
    
    warn "This will permanently delete all DBLab user data:"
    warn "  - Instance configurations"
    warn "  - Database volumes and data"
    warn "  - All stored settings"
    warn "Path: $user_data_dir"
    echo ""
    
    if [[ "$FORCE_MODE" != "true" ]]; then
        read -p "Are you sure you want to remove all user data? (type 'DELETE' to confirm): " -r response
        if [[ "$response" != "DELETE" ]]; then
            info "User data removal cancelled"
            return 0
        fi
    fi
    
    info "Removing user data directory: $user_data_dir"
    
    # Remove data directory with proper ownership handling
    if [[ "$original_user" != "root" ]]; then
        # Change ownership to root temporarily to ensure removal
        chown -R root:root "$user_data_dir" 2>/dev/null || true
    fi
    
    rm -rf "$user_data_dir"
    
    # Also remove parent directories if empty
    local parent_dir
    parent_dir=$(dirname "$user_data_dir")
    if [[ -d "$parent_dir" ]]; then
        rmdir "$parent_dir" 2>/dev/null || true
        parent_dir=$(dirname "$parent_dir")
        if [[ -d "$parent_dir" ]]; then
            rmdir "$parent_dir" 2>/dev/null || true
        fi
    fi
    
    info "User data removed successfully"
}

# Show confirmation
confirm_uninstall() {
    echo "This will remove DBLab from your system."
    echo "Installation directory: $DBLAB_INSTALL_DIR"
    echo "Binary symlink: $DBLAB_BIN_LINK"
    echo ""
    
    if [[ "$REMOVE_USER_DATA" == "true" ]]; then
        warn "User data WILL be removed (--remove-data specified)"
    else
        info "User data will NOT be removed"
    fi
    
    if [[ "$STOP_CONTAINERS" == "true" ]]; then
        warn "Running containers WILL be stopped (--stop-containers specified)"
    else
        info "Running containers will NOT be stopped"
    fi
    
    echo ""
    
    if [[ "$FORCE_MODE" != "true" ]]; then
        read -p "Are you sure you want to uninstall DBLab? (yes/no): " -r response
        
        case "$response" in
            yes|YES|y|Y)
                return 0
                ;;
            *)
                info "Uninstallation cancelled"
                exit 0
                ;;
        esac
    else
        info "Force mode enabled, proceeding with uninstall..."
    fi
}

# Remove files
remove_files() {
    info "Removing DBLab files..."
    
    # Remove installation directory
    if [[ -d "$DBLAB_INSTALL_DIR" ]]; then
        info "Removing $DBLAB_INSTALL_DIR"
        rm -rf "$DBLAB_INSTALL_DIR"
    else
        warn "Installation directory not found: $DBLAB_INSTALL_DIR"
    fi
    
    # Remove symlink
    if [[ -L "$DBLAB_BIN_LINK" ]]; then
        info "Removing $DBLAB_BIN_LINK"
        rm -f "$DBLAB_BIN_LINK"
    elif [[ -f "$DBLAB_BIN_LINK" ]]; then
        warn "Removing unexpected file at $DBLAB_BIN_LINK"
        rm -f "$DBLAB_BIN_LINK"
    fi
    
    # Remove uninstall script (self-removal)
    if [[ -f "$DBLAB_UNINSTALL_SCRIPT" ]]; then
        info "Removing uninstall script"
        rm -f "$DBLAB_UNINSTALL_SCRIPT"
    fi
}

# Main function
main() {
    parse_args "$@"
    check_root
    
    if [[ "$STOP_CONTAINERS" == "true" ]]; then
        stop_dblab_containers
    fi
    
    confirm_uninstall
    remove_files
    
    if [[ "$REMOVE_USER_DATA" == "true" ]]; then
        remove_user_data
    fi
    
    info "DBLab has been successfully uninstalled"
    echo ""
    
    if [[ "$REMOVE_USER_DATA" != "true" ]]; then
        local original_user
        original_user=$(get_original_user)
        local user_data_dir
        
        if [[ "$original_user" != "root" ]]; then
            user_data_dir="/home/$original_user/.local/share/dblab"
        else
            user_data_dir="/root/.local/share/dblab"
        fi
        
        info "Note: User data preserved at: $user_data_dir"
        info "To remove user data: rm -rf $user_data_dir"
    fi
    
    if [[ "$STOP_CONTAINERS" != "true" ]]; then
        info "Note: Running containers were not stopped"
        info "To stop DBLab containers manually:"
        info "  docker stop \$(docker ps --filter 'name=dblab_' -q)"
        info "  podman stop \$(podman ps --filter 'name=dblab_' -q)"
    fi
}

main "$@"
EOF

    chmod +x "$DBLAB_UNINSTALL_SCRIPT"
    debug "Uninstall script created at $DBLAB_UNINSTALL_SCRIPT"
}

# Verify installation
verify_installation() {
    info "Verifying installation..."
    
    # Check if binary is accessible
    if ! command -v dblab >/dev/null 2>&1; then
        die "DBLab binary not found in PATH"
    fi
    
    # Check if binary can show help
    if ! dblab --help >/dev/null 2>&1; then
        die "DBLab binary is not working correctly"
    fi
    
    # Check version
    local installed_version
    if command -v dblab >/dev/null 2>&1; then
        info "DBLab installed successfully"
        info "Version: $DBLAB_VERSION"
        info "Location: $DBLAB_INSTALL_DIR"
    fi
    
    debug "Installation verification passed"
}

# Show post-install information
show_post_install_info() {
    info "Installation completed successfully!"
    echo ""
    echo "Quick start:"
    echo "  dblab init postgres --instance mydb"
    echo "  # Edit mydb.env to set password"
    echo "  dblab up postgres --instance mydb --env-file mydb.env"
    echo ""
    echo "For help:"
    echo "  dblab --help"
    echo ""
    echo "To uninstall:"
    echo "  sudo dblab-uninstall"
    echo ""
    info "User data will be stored in ${DBLAB_USER_DATA_DIR/#\~/$HOME}"
}

# Main installation function
main() {
    local INSTALL_SOURCE=""
    local INSTALL_SOURCE_PATH=""
    local DBLAB_VERSION=""
    
    info "Starting DBLab installation..."
    
    check_root
    check_requirements
    detect_source
    get_version
    remove_existing
    install_files
    create_symlink
    create_uninstall_script
    verify_installation
    show_post_install_info
    
    info "Installation complete!"
    echo ""
    echo "User data will be stored in: ${DBLAB_USER_DATA_DIR/#\~/$HOME}"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
