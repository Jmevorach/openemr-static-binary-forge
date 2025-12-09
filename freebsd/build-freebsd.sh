#!/usr/bin/env bash
# ==============================================================================
# Build OpenEMR Static Binary for FreeBSD using QEMU on macOS
# ==============================================================================
# This script builds a self-contained OpenEMR binary for FreeBSD by:
# 1. Setting up a FreeBSD VM using QEMU on macOS
# 2. Running the build process inside the FreeBSD VM
# 3. Copying the resulting binary back to macOS
#
# QEMU setup based on: https://wiki.freebsd.org/arm64/QEMU
#
# Usage:
#   ./build-freebsd.sh [openemr_version] [freebsd_version]
#
# Example:
#   ./build-freebsd.sh v7_0_3_4 14.0
#
# Requirements:
#   - macOS (Darwin) with Apple Silicon (M1/M2/M3/M4/M5) or Intel
#   - QEMU installed via Homebrew
#   - FreeBSD VM image (will be downloaded automatically)
#   - Internet connection for downloading dependencies
#
# The resulting binary will be in the freebsd/ directory.
# ==============================================================================

# ==============================================================================
# Version Configuration
# ==============================================================================
# All package versions are defined here as environment variables for easy
# maintenance and stability. Override these variables before running the script
# to use different versions.
#
# OpenEMR Configuration:
export OPENEMR_VERSION="${OPENEMR_VERSION:-v7_0_3_4}"
#
# FreeBSD Configuration:
export FREEBSD_VERSION="${FREEBSD_VERSION:-15.0}"
#
# PHP Configuration:
export PHP_VERSION="${PHP_VERSION:-8.5}"
#
# FreeBSD Package Versions (pkg package names with version suffixes):
# Note: These are build-time dependencies used for composer, npm, and PHAR creation.
# The final binary uses PHP built from source (see PHP_VERSION above).
# The package version should match PHP_VERSION when possible (e.g., php85 for PHP 8.5).
# If php85 packages aren't available in FreeBSD repos, override these to use php84, php83, etc. etc..
# These will be derived from PHP_VERSION after it's finalized (see below).
export FREEBSD_PHP_PKG="${FREEBSD_PHP_PKG:-}"
export FREEBSD_PHP_EXTENSIONS_PKG="${FREEBSD_PHP_EXTENSIONS_PKG:-}"
export FREEBSD_PHP_COMPOSER_PKG="${FREEBSD_PHP_COMPOSER_PKG:-}"
export FREEBSD_PHP_ZLIB_PKG="${FREEBSD_PHP_ZLIB_PKG:-}"
export FREEBSD_NODE_PKG="${FREEBSD_NODE_PKG:-node22}"
export FREEBSD_NPM_PKG="${FREEBSD_NPM_PKG:-npm-node22}"
export FREEBSD_PYTHON_PKG="${FREEBSD_PYTHON_PKG:-python311}"
export FREEBSD_GCC_PKG="${FREEBSD_GCC_PKG:-gcc13}"
export FREEBSD_IMAGEMAGICK_PKG="${FREEBSD_IMAGEMAGICK_PKG:-ImageMagick7}"
# ==============================================================================

set -euo pipefail

# Ensure output is unbuffered for streaming to terminal
export PYTHONUNBUFFERED=1
export PHP_BIN_STREAM=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Handle arguments
DEBUG_MODE=false
OPENEMR_TAG=""
FREEBSD_VERSION=""
PHP_VERSION=""
for arg in "$@"; do
    if [[ "${arg}" == "--debug" ]]; then
        DEBUG_MODE=true
    elif [[ "${arg}" == "--help" ]] || [[ "${arg}" == "-h" ]]; then
        echo "Usage: $0 [openemr_version] [freebsd_version] [php_version] [--debug]"
        echo ""
        echo "Arguments:"
        echo "  openemr_version  OpenEMR version tag (default: v7_0_3_4)"
        echo "  freebsd_version  FreeBSD version (default: 15.0)"
        echo "  php_version      PHP version for static build (default: 8.5)"
        echo "  --debug          Preserve build artifacts on failure"
        echo ""
        echo "Examples:"
        echo "  $0 v7_0_3_4 15.0 8.3"
        echo "  $0 v7_0_3_4 15.0 8.4 --debug"
        exit 0
    elif [[ -z "${OPENEMR_TAG}" ]]; then
        OPENEMR_TAG="${arg}"
    elif [[ -z "${FREEBSD_VERSION}" ]]; then
        FREEBSD_VERSION="${arg}"
    elif [[ -z "${PHP_VERSION}" ]]; then
        PHP_VERSION="${arg}"
    fi
done
# Use version variables (allow command-line overrides, fallback to exported defaults)
OPENEMR_TAG="${OPENEMR_TAG:-${OPENEMR_VERSION}}"
FREEBSD_VERSION="${FREEBSD_VERSION:-15.0}"
PHP_VERSION="${PHP_VERSION:-8.5}"

# Derive FreeBSD PHP package versions from PHP_VERSION if not explicitly set
# This ensures we use php85 for PHP 8.5, php84 for PHP 8.4, etc.
if [ -z "${FREEBSD_PHP_PKG}" ]; then
    PHP_MAJOR_MINOR=$(echo "${PHP_VERSION}" | cut -d. -f1,2 | tr -d '.')
    export FREEBSD_PHP_PKG="php${PHP_MAJOR_MINOR}"
    export FREEBSD_PHP_EXTENSIONS_PKG="php${PHP_MAJOR_MINOR}-extensions"
    export FREEBSD_PHP_COMPOSER_PKG="php${PHP_MAJOR_MINOR}-composer"
    export FREEBSD_PHP_ZLIB_PKG="php${PHP_MAJOR_MINOR}-zlib"
fi

if [[ "${DEBUG_MODE}" == "true" ]]; then
    echo -e "${YELLOW}[DEBUG MODE ENABLED]${NC}"
fi

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Building OpenEMR Static Binary for FreeBSD using QEMU${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""

echo "OpenEMR Version: ${OPENEMR_TAG}"
echo "FreeBSD Version: ${FREEBSD_VERSION}"
echo "PHP Version: ${PHP_VERSION}"
echo "Project Root: ${PROJECT_ROOT}"
echo "Build Directory: ${SCRIPT_DIR}"
echo ""

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}ERROR: This script is designed for macOS only${NC}"
    echo "It uses QEMU to run FreeBSD in a virtual machine."
    exit 1
fi

# Detect architecture
ARCH=$(uname -m)
if [ "${ARCH}" = "arm64" ]; then
    QEMU_ARCH="aarch64"
    FREEBSD_ARCH="arm64"
    echo "Detected: Apple Silicon (ARM64)"
elif [ "${ARCH}" = "x86_64" ]; then
    QEMU_ARCH="x86_64"
    FREEBSD_ARCH="amd64"
    echo "Detected: Intel (x86_64)"
else
    echo -e "${RED}ERROR: Unsupported architecture: ${ARCH}${NC}"
    exit 1
fi

echo ""

# Check required tools
echo -e "${YELLOW}Checking requirements...${NC}"
MISSING_TOOLS=()

if ! command -v qemu-system-${QEMU_ARCH} >/dev/null 2>&1; then
    MISSING_TOOLS+=("qemu")
fi

if ! command -v git >/dev/null 2>&1; then
    MISSING_TOOLS+=("git")
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo -e "${RED}ERROR: Missing required tools: ${MISSING_TOOLS[*]}${NC}"
    echo ""
    echo "Install missing tools:"
    for tool in "${MISSING_TOOLS[@]}"; do
        case "${tool}" in
            qemu)
                echo "  - QEMU: brew install qemu"
                ;;
            git)
                echo "  - Git: xcode-select --install (or install Xcode)"
                ;;
        esac
    done
    exit 1
fi

echo -e "${GREEN}✓ All required tools are available${NC}"
echo ""

# Detect system resources
echo -e "${YELLOW}Detecting system resources...${NC}"

# Detect CPU cores
if command -v sysctl >/dev/null 2>&1; then
    CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "2")
    PHYSICAL_CORES=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "${CPU_CORES}")
    TOTAL_RAM_GB=$(($(sysctl -n hw.memsize 2>/dev/null || echo "8589934592") / 1024 / 1024 / 1024))
else
    CPU_CORES=2
    PHYSICAL_CORES=2
    TOTAL_RAM_GB=8
fi

# Calculate optimal parallel jobs
PARALLEL_JOBS=$((PHYSICAL_CORES + 1))
if [ "${PARALLEL_JOBS}" -gt "${CPU_CORES}" ]; then
    PARALLEL_JOBS="${CPU_CORES}"
fi
if [ "${PARALLEL_JOBS}" -lt 2 ]; then
    PARALLEL_JOBS=2
fi

echo "System resources detected:"
echo "  CPU cores (logical): ${CPU_CORES}"
echo "  CPU cores (physical): ${PHYSICAL_CORES}"
echo "  Total RAM: ${TOTAL_RAM_GB} GB"
echo "  Optimal parallel jobs: ${PARALLEL_JOBS}"
echo ""

# Set VM memory (allocate 50% of system RAM, minimum 4GB, maximum 16GB)
VM_RAM_GB=$((TOTAL_RAM_GB / 2))
if [ "${VM_RAM_GB}" -lt 4 ]; then
    VM_RAM_GB=4
fi
if [ "${VM_RAM_GB}" -gt 16 ]; then
    VM_RAM_GB=16
fi

echo "QEMU VM configuration:"
echo "  VM RAM: ${VM_RAM_GB} GB"
echo "  Architecture: ${FREEBSD_ARCH}"
echo ""

# Note: We use dynamic ports for HTTP server and serial console to avoid conflicts

# Create temporary directory for building
TMP_DIR=$(mktemp -d)
BUILD_DIR="${TMP_DIR}/build"
VM_DIR="${TMP_DIR}/vm"
mkdir -p "${BUILD_DIR}" "${VM_DIR}"

# Debug mode: preserve build artifacts on failure
if [[ "${DEBUG_MODE}" == "true" ]]; then
    echo -e "${YELLOW}DEBUG MODE ENABLED: Build artifacts will be preserved on failure${NC}"
fi

# Ensure cleanup on exit - consolidated cleanup function for all resources
CLEANUP_EXIT_CODE=0
QEMU_PID=""
HTTP_SERVER_PID=""

cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up resources...${NC}"
    
    # Stop HTTP server if running
    if [ -n "${HTTP_SERVER_PID:-}" ] && kill -0 "${HTTP_SERVER_PID}" 2>/dev/null; then
        echo "Stopping HTTP server (PID: ${HTTP_SERVER_PID})..."
        kill "${HTTP_SERVER_PID}" 2>/dev/null || true
        sleep 1
        if kill -0 "${HTTP_SERVER_PID}" 2>/dev/null; then
            kill -9 "${HTTP_SERVER_PID}" 2>/dev/null || true
        fi
    fi
    
    # Stop QEMU VM if running - use graceful shutdown to avoid filesystem corruption
    if [ -n "${QEMU_PID:-}" ] && kill -0 "${QEMU_PID}" 2>/dev/null; then
        echo "Stopping QEMU VM gracefully (PID: ${QEMU_PID})..."
        # First try SIGTERM which QEMU handles by initiating ACPI shutdown
        kill -TERM "${QEMU_PID}" 2>/dev/null || true
        # Wait up to 10 seconds for graceful shutdown
        for i in $(seq 1 10); do
            if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
                echo "VM stopped gracefully"
                break
            fi
            sleep 1
        done
        # Force kill if still running
        if kill -0 "${QEMU_PID}" 2>/dev/null; then
            echo "Force killing VM..."
            kill -9 "${QEMU_PID}" 2>/dev/null || true
        fi
    fi
    
    # Clean up temp directory
    if [ -n "${TMP_DIR:-}" ] && [ -d "${TMP_DIR}" ]; then
        if [[ "${DEBUG_MODE}" == "true" ]] && [ ${CLEANUP_EXIT_CODE:-0} -ne 0 ]; then
            echo ""
            echo -e "${YELLOW}============================================================================${NC}"
            echo -e "${YELLOW}DEBUG MODE: Preserving build artifacts${NC}"
            echo -e "${YELLOW}============================================================================${NC}"
            echo ""
            echo "Build directory preserved at: ${TMP_DIR}"
            echo ""
        elif [[ "${DEBUG_MODE}" != "true" ]]; then
            rm -rf "${TMP_DIR}"
        fi
    fi
    
    echo -e "${GREEN}Cleanup complete.${NC}"
}

trap 'CLEANUP_EXIT_CODE=$?; cleanup; exit ${CLEANUP_EXIT_CODE}' EXIT INT TERM

cd "${BUILD_DIR}"

# Step 1: Download FreeBSD VM image
echo -e "${YELLOW}Step 1/6: Setting up FreeBSD VM image...${NC}"

# FreeBSD uses aarch64 in VM-IMAGES, not arm64
VM_ARCH="${FREEBSD_ARCH}"
if [ "${FREEBSD_ARCH}" = "arm64" ]; then
    VM_ARCH="aarch64"
fi

# FreeBSD 15.0 VM image - always download fresh to avoid corruption issues
FREEBSD_IMAGE_NAME="FreeBSD-${FREEBSD_VERSION}-RELEASE-${FREEBSD_ARCH}-${VM_ARCH}-ufs.qcow2"
FREEBSD_IMAGE_URL="https://download.freebsd.org/releases/VM-IMAGES/${FREEBSD_VERSION}-RELEASE/${VM_ARCH}/Latest/${FREEBSD_IMAGE_NAME}.xz"
FREEBSD_IMAGE="${VM_DIR}/${FREEBSD_IMAGE_NAME}"

echo "Downloading fresh FreeBSD ${FREEBSD_VERSION} ${FREEBSD_ARCH} VM image..."
echo "URL: ${FREEBSD_IMAGE_URL}"
echo "This may take several minutes depending on your internet connection..."
echo ""

if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}ERROR: curl is required to download FreeBSD VM image${NC}"
    exit 1
fi

curl -L -f --progress-bar -o "${FREEBSD_IMAGE}.xz" "${FREEBSD_IMAGE_URL}" || {
    echo -e "${RED}ERROR: Failed to download FreeBSD VM image${NC}"
    echo "URL: ${FREEBSD_IMAGE_URL}"
    exit 1
}

echo "Extracting FreeBSD VM image..."
if ! command -v xz >/dev/null 2>&1; then
    echo -e "${RED}ERROR: xz is required to extract FreeBSD VM image${NC}"
    echo "Install with: brew install xz"
    exit 1
fi
xz -d "${FREEBSD_IMAGE}.xz"

# Resize the disk image to 20GB (default is only ~6GB which isn't enough for OpenEMR)
echo "Resizing VM disk to 20GB for OpenEMR build..."
qemu-img resize "${FREEBSD_IMAGE}" 20G
echo -e "${GREEN}✓ VM disk resized to 20GB${NC}"

echo -e "${GREEN}✓ FreeBSD VM image ready${NC}"
echo ""

# Step 2: Create build script for FreeBSD VM
echo -e "${YELLOW}Step 2/6: Preparing build script for FreeBSD VM...${NC}"

# Create a build script that will run inside FreeBSD
cat > "${BUILD_DIR}/freebsd-build.sh" << 'FREEBUILD'
#!/bin/sh
# Don't use set -e initially - handle errors manually for pkg commands
# We'll enable it later after packages are installed

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Building OpenEMR Static Binary inside FreeBSD VM${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""

# Install required packages
echo -e "${YELLOW}Installing required FreeBSD packages...${NC}"

# Install pkg if not already installed (non-interactive)
if ! command -v pkg >/dev/null 2>&1; then
    echo "Installing pkg package manager..."
    
    # Method 1: Download and extract pkg-static from bootstrap tarball (FreeBSD handbook method)
    echo "Downloading pkg bootstrap tarball..."
    BOOTSTRAP_URL="https://pkg.freebsd.org/FreeBSD:15:aarch64/bootstrap.txz"
    TMP_DIR="/tmp/pkg-bootstrap"
    mkdir -p "${TMP_DIR}"
    cd "${TMP_DIR}"
    
    if fetch -o "bootstrap.txz" "${BOOTSTRAP_URL}"; then
        echo "Extracting bootstrap tarball..."
        tar -xzf bootstrap.txz
        
        # According to FreeBSD handbook, extract pkg-static and pkg.txz
        # The structure should have pkg-static and pkg.txz in the root
        if [ -f "pkg-static" ]; then
            echo "Found pkg-static, installing pkg..."
            chmod +x pkg-static
            
            # Try to find pkg.txz - it might be in the root or in a subdirectory
            PKG_TXZ=""
            if [ -f "pkg.txz" ]; then
                PKG_TXZ="pkg.txz"
            else
                PKG_TXZ=$(find . -name "pkg*.txz" -type f | head -1)
            fi
            
            if [ -n "${PKG_TXZ}" ] && [ -f "${PKG_TXZ}" ]; then
                echo "Installing pkg using: ./pkg-static add ${PKG_TXZ}"
                # Use -f flag to force installation
                ./pkg-static add -f "${PKG_TXZ}" 2>&1 || {
                    echo "pkg-static add failed, trying install from repo..."
                    # Try installing from repository with non-interactive flags
                    ASSUME_ALWAYS_YES=yes ./pkg-static install -y pkg 2>&1 || true
                }
            else
                echo "pkg.txz not found in bootstrap, trying install from repo..."
                ASSUME_ALWAYS_YES=yes ./pkg-static install -y pkg 2>&1 || true
            fi
            
            # Verify pkg is now installed
            if command -v pkg >/dev/null 2>&1; then
                echo "✓ pkg successfully installed via bootstrap tarball"
            else
                echo "✗ pkg installation failed, will try alternative methods"
            fi
        else
            echo "pkg-static not found in bootstrap tarball structure:"
            ls -la
            echo "Trying alternative method..."
        fi
    else
        echo "Failed to download bootstrap tarball"
    fi
    
    cd /
    rm -rf "${TMP_DIR}"
    
    # Method 2: If pkg still not installed, try /usr/sbin/pkg bootstrap with environment variable
    if ! command -v pkg >/dev/null 2>&1; then
        if [ -f /usr/sbin/pkg ]; then
            echo "Trying /usr/sbin/pkg bootstrap with ASSUME_ALWAYS_YES..."
            # Set environment variable and pipe yes to handle any remaining prompts
            (export ASSUME_ALWAYS_YES=yes; yes | /usr/sbin/pkg bootstrap 2>&1) || true
            
            # Verify installation
            if command -v pkg >/dev/null 2>&1; then
                echo "✓ pkg successfully installed via /usr/sbin/pkg bootstrap"
            fi
        fi
    fi
    
    # Method 3: Final fallback - try pkg-static from base if available
    if ! command -v pkg >/dev/null 2>&1 && command -v pkg-static >/dev/null 2>&1; then
        echo "Trying pkg-static from base system..."
        ASSUME_ALWAYS_YES=yes pkg-static install -y pkg 2>&1 || true
        
        # Verify installation
        if command -v pkg >/dev/null 2>&1; then
            echo "✓ pkg successfully installed via pkg-static"
        fi
    fi
    
    # Final check - if pkg is still not installed, this is a problem
    if ! command -v pkg >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Failed to install pkg package manager. Cannot continue.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ pkg package manager is installed${NC}"
fi

# Make all pkg commands non-interactive
export ASSUME_ALWAYS_YES=yes

echo "Updating package repository..."
pkg update -f || {
    echo "WARNING: pkg update failed, trying to continue..."
}

echo "Installing build dependencies for static PHP compilation..."
# Install system PHP for initial build steps (composer, npm)
# Plus all development libraries needed to compile PHP from source
pkg install -y \
    git \
    ${FREEBSD_PHP_PKG} \
    ${FREEBSD_PHP_EXTENSIONS_PKG} \
    ${FREEBSD_PHP_COMPOSER_PKG} \
    ${FREEBSD_PHP_ZLIB_PKG} \
    ${FREEBSD_NODE_PKG} \
    ${FREEBSD_NPM_PKG} \
    curl \
    wget \
    gmake \
    autoconf \
    automake \
    libtool \
    pkgconf \
    bison \
    re2c \
    libxml2 \
    libxslt \
    icu \
    oniguruma \
    sqlite3 \
    openssl \
    libsodium \
    libzip \
    libiconv \
    gettext-runtime \
    gettext-tools \
    png \
    libjpeg-turbo \
    freetype2 \
    webp \
    curl \
    bzip2 \
    ${FREEBSD_IMAGEMAGICK_PKG} \
    ${FREEBSD_GCC_PKG} \
    llvm \
    ${FREEBSD_PYTHON_PKG} \
    python3 \
    bash || {
    echo -e "${RED}ERROR: Failed to install some packages${NC}"
    echo "Trying to continue anyway..."
}

echo -e "${GREEN}✓ Package installation completed${NC}"
echo ""

# Now enable strict error handling for the rest of the build
set -e

# Set up build environment
BUILD_DIR="/build"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Clone OpenEMR (remove existing directory if present)
echo -e "${YELLOW}Cloning OpenEMR ${OPENEMR_TAG}...${NC}"
rm -rf openemr-source 2>/dev/null || true
git clone --depth 1 --branch "${OPENEMR_TAG}" https://github.com/openemr/openemr.git openemr-source || {
    echo -e "${RED}ERROR: Failed to clone OpenEMR${NC}"
    exit 1
}

cd openemr-source

# Prepare OpenEMR for PHAR creation
echo "Preparing application for PHAR creation..."
mkdir -p "${BUILD_DIR}/openemr-phar"
git archive HEAD | tar -x -C "${BUILD_DIR}/openemr-phar"

cd "${BUILD_DIR}/openemr-phar"

# Remove unneeded files
echo "Removing unneeded files..."
rm -rf .git tests/ .github/ docs/ 2>/dev/null || true

# Use PHP binary from standard FreeBSD package location
# FreeBSD packages install PHP at /usr/local/bin/php (regardless of version)
PHP_BIN="/usr/local/bin/php"

if [ ! -f "${PHP_BIN}" ] || [ ! -x "${PHP_BIN}" ]; then
    echo -e "${RED}ERROR: PHP binary not found at ${PHP_BIN}${NC}"
    echo ""
    echo "PHP package installed: ${FREEBSD_PHP_PKG}"
    echo "PHP version: ${PHP_VERSION}"
    echo ""
    echo "Installed PHP packages:"
    pkg info | grep -E "^php[0-9]" || pkg info | grep php || true
    echo ""
    echo "Files in /usr/local/bin matching php*:"
    ls -la /usr/local/bin/php* 2>/dev/null || echo "  (none found)"
    echo ""
    echo "Please ensure PHP package ${FREEBSD_PHP_PKG} is installed correctly."
    exit 1
fi

echo "Using PHP binary: ${PHP_BIN}"
${PHP_BIN} -v || {
    echo -e "${RED}ERROR: PHP binary found but not working${NC}"
    exit 1
}

# Install production dependencies
echo "Installing production dependencies..."
if [ -f "composer.json" ] && command -v composer >/dev/null 2>&1; then
    composer install \
        --ignore-platform-reqs \
        --no-dev \
        --optimize-autoloader \
        --prefer-dist \
        --no-interaction || {
        echo -e "${YELLOW}WARNING: Composer install had issues, but continuing...${NC}"
    }
fi

# Build frontend assets (may occasionally cause build issues but is important for full functionality)
# Ensure PATH includes /usr/local/bin where npm is installed
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:${PATH}"

echo "Checking for npm and package.json..."
if [ -f "package.json" ]; then
    echo "  ✓ package.json found"
else
    echo "  ✗ package.json not found"
fi

# Try to find npm - check multiple locations and names
NPM_CMD=""
if command -v npm >/dev/null 2>&1; then
    NPM_CMD="npm"
    echo "  ✓ npm found at: $(command -v npm)"
elif [ -x "/usr/local/bin/npm" ]; then
    NPM_CMD="/usr/local/bin/npm"
    echo "  ✓ npm found at: /usr/local/bin/npm"
elif command -v npm-node22 >/dev/null 2>&1; then
    NPM_CMD="npm-node22"
    echo "  ✓ npm-node22 found at: $(command -v npm-node22)"
    # Create symlink so npm command works
    ln -sf "$(command -v npm-node22)" /usr/local/bin/npm 2>/dev/null || true
    if [ -x "/usr/local/bin/npm" ]; then
        NPM_CMD="npm"
        echo "  ✓ Created npm symlink"
    fi
elif [ -x "/usr/local/bin/npm-node22" ]; then
    NPM_CMD="/usr/local/bin/npm-node22"
    echo "  ✓ npm-node22 found at: /usr/local/bin/npm-node22"
    # Create symlink so npm command works
    ln -sf /usr/local/bin/npm-node22 /usr/local/bin/npm 2>/dev/null || true
    if [ -x "/usr/local/bin/npm" ]; then
        NPM_CMD="npm"
        echo "  ✓ Created npm symlink"
    fi
else
    # Check if npm package is installed via pkg
    echo "  Checking pkg database for npm packages..."
    INSTALLED_NPM=$(pkg info -q | grep -E "^npm" | head -1)
    if [ -n "${INSTALLED_NPM}" ]; then
        echo "  Found installed npm package: ${INSTALLED_NPM}"
        # Try to find where it installed the binary
        NPM_BIN=$(pkg query "%b" "${INSTALLED_NPM}" 2>/dev/null | grep -E "bin/npm" | head -1)
        if [ -n "${NPM_BIN}" ] && [ -x "${NPM_BIN}" ]; then
            NPM_CMD="${NPM_BIN}"
            echo "  ✓ Found npm binary via pkg query: ${NPM_BIN}"
        else
            # Try common locations for the package
            for possible_path in "/usr/local/bin/${INSTALLED_NPM}" "/usr/local/bin/npm" "/usr/local/bin/npm-node22" "/usr/local/bin/npm-node20" "/usr/local/bin/npm-node18"; do
                if [ -x "${possible_path}" ]; then
                    NPM_CMD="${possible_path}"
                    echo "  ✓ Found npm at: ${possible_path}"
                    break
                fi
            done
        fi
    fi
    
    # Last resort: search for any npm* binary in common locations
    if [ -z "${NPM_CMD}" ]; then
        for search_dir in /usr/local/bin /usr/local/libexec/npm /opt/local/bin; do
            if [ -d "${search_dir}" ]; then
                NPM_BIN=$(find "${search_dir}" -name "npm*" -type f -executable 2>/dev/null | head -1)
                if [ -n "${NPM_BIN}" ]; then
                    NPM_CMD="${NPM_BIN}"
                    echo "  ✓ Found npm binary via find: ${NPM_BIN}"
                    break
                fi
            fi
        done
    fi
    
    # Create symlink if we found npm but it's not named "npm"
    if [ -n "${NPM_CMD}" ] && [ "${NPM_CMD}" != "npm" ] && [ "${NPM_CMD}" != "/usr/local/bin/npm" ]; then
        echo "  Creating symlink: /usr/local/bin/npm -> ${NPM_CMD}"
        ln -sf "${NPM_CMD}" /usr/local/bin/npm 2>/dev/null || true
        if [ -x "/usr/local/bin/npm" ]; then
            NPM_CMD="npm"
            echo "  ✓ Created npm symlink"
        fi
    fi
    
    if [ -z "${NPM_CMD}" ]; then
        echo "  ✗ ERROR: npm not found anywhere"
        echo "  Searched in:"
        echo "    - PATH: $(echo $PATH | tr ':' '\n' | head -5)"
        echo "    - /usr/local/bin/npm"
        echo "    - /usr/local/bin/npm-node22"
        echo "    - All npm* files in /usr/local/bin"
        echo ""
        echo "  Installed node packages:"
        pkg info | grep -E "^node|^npm" || echo "    (none found)"
        echo ""
        echo "  Files in /usr/local/bin matching npm*:"
        ls -la /usr/local/bin/npm* 2>/dev/null || echo "    (none found)"
        echo ""
        echo "  Attempting to install npm-node22..."
        pkg install -y npm-node22 2>&1 | tail -5 || echo "    (installation failed)"
        # Try one more time after installation attempt
        if [ -x "/usr/local/bin/npm-node22" ]; then
            NPM_CMD="/usr/local/bin/npm-node22"
            ln -sf /usr/local/bin/npm-node22 /usr/local/bin/npm 2>/dev/null || true
            if [ -x "/usr/local/bin/npm" ]; then
                NPM_CMD="npm"
                echo "  ✓ npm installed and symlink created"
            fi
        fi
    fi
fi

if [ -n "${NPM_CMD}" ]; then
    echo "  Using npm: ${NPM_CMD}"
    ${NPM_CMD} --version 2>&1 || echo "    (version check failed)"
fi

if [ -f "package.json" ] && [ -n "${NPM_CMD}" ]; then
    echo "Building frontend assets..."
    
    # Make npm fully non-interactive
    export npm_config_yes=true
    export npm_config_loglevel=warn
    export CI=true
    
    # Install global dependencies needed by OpenEMR's postinstall scripts
    echo "Installing global npm dependencies (napa, gulp-cli)..."
    ${NPM_CMD} install -g --yes napa gulp-cli 2>&1 || {
        echo -e "${YELLOW}WARNING: Failed to install global npm deps${NC}"
    }
    
    # Install npm dependencies (WITHOUT --production flag to get devDependencies needed for building)
    echo "Installing npm dependencies (including devDependencies for build tools)..."
    echo "Current directory: $(pwd)"
    echo "npm version: $(${NPM_CMD} --version 2>&1 || echo 'unknown')"
    echo "node version: $(node --version 2>&1 || echo 'unknown')"
    
    ${NPM_CMD} ci 2>&1 || {
        echo -e "${YELLOW}WARNING: npm ci had issues, trying npm install as fallback...${NC}"
        ${NPM_CMD} install 2>&1 || {
            echo -e "${YELLOW}WARNING: npm install also had issues, but continuing...${NC}"
        }
    }
    
    echo "npm dependencies installed. Checking node_modules..."
    if [ -d "node_modules" ]; then
        echo "  ✓ node_modules directory exists"
        MODULE_COUNT=$(find node_modules -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        echo "  Found ${MODULE_COUNT} modules"
    else
        echo -e "${YELLOW}  WARNING: node_modules directory not found${NC}"
    fi
    
    # Run build command to compile CSS/JS assets
    # OpenEMR uses Gulp via npm run build to compile CSS and JavaScript
    echo "Building frontend assets with npm run build (runs Gulp)..."
    BUILD_SUCCESS=false
    
    # OpenEMR uses 'npm run build' which triggers Gulp to compile assets
    echo "Checking available npm scripts..."
    ${NPM_CMD} run 2>&1 | head -20 || echo "Could not list npm scripts"
    
    if ${NPM_CMD} run 2>&1 | grep -q "^  build" || grep -q '"build"' package.json 2>/dev/null; then
        echo "Running npm run build to compile CSS and JavaScript assets..."
        echo "This may take several minutes..."
        ${NPM_CMD} run build 2>&1 | tee /tmp/npm-build.log && {
            BUILD_SUCCESS=true
            echo -e "${GREEN}✓ Frontend assets built successfully (CSS and JavaScript compiled)${NC}"
        } || {
            echo -e "${YELLOW}WARNING: npm run build had issues${NC}"
            echo "Last 20 lines of build output:"
            tail -20 /tmp/npm-build.log 2>/dev/null || true
        }
    else
        echo "npm run build script not found, trying gulp directly..."
        # Fallback: try gulp directly if npm run build doesn't exist
        if command -v gulp >/dev/null 2>&1 && ([ -f "gulpfile.js" ] || [ -f "Gulpfile.js" ]); then
            echo "Running gulp directly to build frontend assets..."
            echo "This may take several minutes..."
            gulp 2>&1 | tee /tmp/gulp-build.log && {
                BUILD_SUCCESS=true
                echo -e "${GREEN}✓ Gulp build completed successfully${NC}"
            } || {
                echo -e "${YELLOW}WARNING: gulp build had issues${NC}"
                echo "Last 20 lines of build output:"
                tail -20 /tmp/gulp-build.log 2>/dev/null || true
            }
        else
            echo -e "${YELLOW}WARNING: Neither npm run build nor gulp found${NC}"
            echo "gulp command: $(command -v gulp 2>&1 || echo 'not found')"
            echo "gulpfile.js exists: $([ -f "gulpfile.js" ] && echo 'yes' || echo 'no')"
        fi
    fi
    
    if [ "${BUILD_SUCCESS}" != "true" ]; then
        echo -e "${RED}ERROR: Frontend build failed!${NC}"
        echo -e "${RED}CSS and JavaScript assets were NOT compiled.${NC}"
        echo -e "${RED}OpenEMR will not have working styles or JavaScript.${NC}"
        echo ""
        echo "Debugging information:"
        echo "  - Current directory: $(pwd)"
        echo "  - npm location: ${NPM_CMD:-'not found'}"
        echo "  - node location: $(command -v node 2>&1 || echo 'not found')"
        echo "  - gulp location: $(command -v gulp 2>&1 || echo 'not found')"
        echo "  - package.json exists: $([ -f "package.json" ] && echo 'yes' || echo 'no')"
        echo "  - gulpfile.js exists: $([ -f "gulpfile.js" ] && echo 'yes' || echo 'no')"
        echo "  - node_modules exists: $([ -d "node_modules" ] && echo 'yes' || echo 'no')"
        echo ""
        echo "This is a critical issue. Please check:"
        echo "  - Node.js and npm are properly installed"
        echo "  - All npm dependencies installed correctly"
        echo "  - gulp-cli is installed globally"
        exit 1
    fi
    
    # Verify that frontend assets were actually built
    echo "Verifying frontend assets were built..."
    ASSETS_FOUND=false
    
    # Check for common OpenEMR asset locations
    if [ -d "public/assets" ] && [ "$(find public/assets -type f 2>/dev/null | wc -l)" -gt 0 ]; then
        echo "  ✓ Found assets in public/assets/"
        ASSETS_FOUND=true
    fi
    
    if [ -d "interface/main/css" ] && [ "$(find interface/main/css -name "*.css" 2>/dev/null | wc -l)" -gt 0 ]; then
        echo "  ✓ Found CSS files in interface/main/css/"
        ASSETS_FOUND=true
    fi
    
    if [ -d "interface/main/js" ] && [ "$(find interface/main/js -name "*.js" 2>/dev/null | wc -l)" -gt 0 ]; then
        echo "  ✓ Found JS files in interface/main/js/"
        ASSETS_FOUND=true
    fi
    
    # Check for gulp output directories
    if [ -d "gulp" ] && [ "$(find gulp -type f 2>/dev/null | wc -l)" -gt 0 ]; then
        echo "  ✓ Found gulp output files"
        ASSETS_FOUND=true
    fi
    
    # List some example files to verify
    echo "Sample of built asset files:"
    find . -type f \( -name "*.css" -o -name "*.js" \) -path "*/public/*" -o -path "*/interface/*" 2>/dev/null | head -10 || true
    
    if [ "${ASSETS_FOUND}" != "true" ]; then
        echo -e "${YELLOW}WARNING: Could not verify frontend assets were built${NC}"
        echo "This may cause display issues. Continuing anyway..."
    else
        echo -e "${GREEN}✓ Frontend assets verified${NC}"
    fi
    
    echo -e "${GREEN}Frontend build step completed successfully.${NC}"
fi

# Create PHAR file
echo "=== STEP: Creating PHAR archive ==="
cat > "${BUILD_DIR}/create-phar.php" << 'PHARBUILDER'
<?php
ini_set('phar.readonly', '0');

$pharFile = $argv[1];
$sourceDir = $argv[2];

if (file_exists($pharFile)) {
    unlink($pharFile);
}

$phar = new Phar($pharFile);
$phar->buildFromDirectory($sourceDir);
$phar->setStub($phar->createDefaultStub('interface/main/main.php'));

// Compress if zlib is available
if (extension_loaded('zlib')) {
    $phar->compressFiles(Phar::GZ);
    echo "PHAR created with GZ compression: $pharFile\n";
} else {
    echo "WARNING: zlib not available, PHAR created without compression: $pharFile\n";
}
PHARBUILDER

echo "Running PHAR builder..."
echo "Source directory: ${BUILD_DIR}/openemr-phar"
echo "Verifying source directory contains frontend assets before PHAR creation..."
if [ -d "${BUILD_DIR}/openemr-phar/public/assets" ]; then
    ASSET_COUNT=$(find "${BUILD_DIR}/openemr-phar/public/assets" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  Found ${ASSET_COUNT} files in public/assets/"
fi
if [ -d "${BUILD_DIR}/openemr-phar/interface/main/css" ]; then
    CSS_COUNT=$(find "${BUILD_DIR}/openemr-phar/interface/main/css" -name "*.css" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Found ${CSS_COUNT} CSS files in interface/main/css/"
fi
if [ -d "${BUILD_DIR}/openemr-phar/interface/main/js" ]; then
    JS_COUNT=$(find "${BUILD_DIR}/openemr-phar/interface/main/js" -name "*.js" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Found ${JS_COUNT} JS files in interface/main/js/"
fi

${PHP_BIN} -d phar.readonly=0 -d display_errors=1 -d error_reporting=E_ALL "${BUILD_DIR}/create-phar.php" "${BUILD_DIR}/openemr.phar" "${BUILD_DIR}/openemr-phar" 2>&1 || {
    echo -e "${RED}ERROR: PHP PHAR builder failed with exit code $?${NC}"
    exit 1
}

if [ ! -f "${BUILD_DIR}/openemr.phar" ]; then
    echo -e "${RED}ERROR: Failed to create PHAR file - file not found${NC}"
    exit 1
fi

# Verify PHAR contains frontend assets
echo "Verifying PHAR contains frontend assets..."
PHAR_SIZE=$(stat -f%z "${BUILD_DIR}/openemr.phar" 2>/dev/null || stat -c%s "${BUILD_DIR}/openemr.phar" 2>/dev/null || echo "unknown")
echo "  PHAR size: ${PHAR_SIZE} bytes"

# Try to list some files from the PHAR to verify assets are included
${PHP_BIN} -r "\$phar = new Phar('${BUILD_DIR}/openemr.phar'); \$files = \$phar->getFiles(); \$assetFiles = array_filter(\$files, function(\$f) { return strpos(\$f, 'public/assets') !== false || strpos(\$f, 'interface/main/css') !== false || strpos(\$f, 'interface/main/js') !== false; }); echo 'Found ' . count(\$assetFiles) . ' frontend asset files in PHAR\n'; if (count(\$assetFiles) > 0) { echo 'Sample files:\n'; foreach (array_slice(\$assetFiles, 0, 5) as \$file) { echo '  - ' . \$file . '\n'; } }" 2>/dev/null || {
    echo "  (Could not verify PHAR contents, but PHAR was created)"
}

echo -e "${GREEN}✓ PHAR created${NC}"
echo ""

# Build static PHP from source
# This creates a fully statically linked PHP binary with all required extensions
echo "=== STEP: Building static PHP ${PHP_VERSION} from source ==="
echo -e "${YELLOW}Building static PHP ${PHP_VERSION} from source...${NC}"
echo "This may take 30-60 minutes..."
echo ""

PHP_SRC_DIR="${BUILD_DIR}/php-src"
PHP_INSTALL_DIR="${BUILD_DIR}/php-static"

# Clean up any existing PHP build directories
rm -rf "${PHP_SRC_DIR}" "${PHP_INSTALL_DIR}" 2>/dev/null || true
mkdir -p "${PHP_INSTALL_DIR}"

# Download PHP source
echo "Downloading PHP ${PHP_VERSION} source..."
cd "${BUILD_DIR}"

# Try to get the exact version, fall back to latest in series
PHP_TARBALL="php-${PHP_VERSION}.tar.xz"
PHP_URL="https://www.php.net/distributions/${PHP_TARBALL}"

# For development versions like 8.5, we need to get from GitHub
if ! fetch -o "${PHP_TARBALL}" "${PHP_URL}" 2>/dev/null; then
    echo "Release tarball not found, trying GitHub for PHP ${PHP_VERSION}..."
    PHP_BRANCH="PHP-${PHP_VERSION}"
    git clone --depth=1 --branch "${PHP_BRANCH}" https://github.com/php/php-src.git "${PHP_SRC_DIR}" 2>/dev/null || {
        echo "Branch ${PHP_BRANCH} not found, trying master..."
        git clone --depth=1 https://github.com/php/php-src.git "${PHP_SRC_DIR}"
    }
else
    echo "Extracting PHP source..."
    tar -xf "${PHP_TARBALL}"
    mv "php-${PHP_VERSION}"* "${PHP_SRC_DIR}" 2>/dev/null || mv php-* "${PHP_SRC_DIR}"
fi

cd "${PHP_SRC_DIR}"

# Generate configure script if building from git
if [ -f "buildconf" ]; then
    echo "Running buildconf..."
    ./buildconf --force
fi

# Configure PHP with static linking and required extensions
# Configure PHP with all required extensions for OpenEMR
# FreeBSD has libraries in /usr/local, need to set proper paths
echo "Configuring PHP with all required extensions..."

# Set up compiler flags for FreeBSD
# Include and library paths for FreeBSD's /usr/local prefix
export CFLAGS="-O2 -I/usr/local/include -I/usr/local/include/libpng16 -I/usr/local/include/freetype2"
export CXXFLAGS="-O2 -I/usr/local/include -I/usr/local/include/libpng16 -I/usr/local/include/freetype2"
export CPPFLAGS="-I/usr/local/include -I/usr/local/include/libpng16 -I/usr/local/include/freetype2"
# Link against libraries in /usr/local/lib with rpath so the binary finds them
export LDFLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib"
export LIBS="-lm -lpthread -lstdc++ -lintl -liconv -lz"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/libdata/pkgconfig"

# Use clang (FreeBSD default)
export CC=clang
export CXX=clang++

# Configure with ALL extensions required by OpenEMR
# Explicit paths for FreeBSD's /usr/local prefix
./configure \
    --prefix="${PHP_INSTALL_DIR}" \
    --enable-cli \
    --disable-cgi \
    --disable-phpdbg \
    --enable-bcmath \
    --enable-calendar \
    --enable-exif \
    --enable-ftp \
    --enable-intl \
    --enable-mbstring \
    --enable-mysqlnd \
    --enable-opcache \
    --enable-pcntl \
    --enable-pdo \
    --enable-soap \
    --enable-sockets \
    --with-gettext=/usr/local \
    --with-gd \
    --with-jpeg=/usr/local \
    --with-freetype=/usr/local \
    --with-webp=/usr/local \
    --with-iconv=/usr/local \
    --with-mysqli=mysqlnd \
    --with-openssl=/usr/local \
    --with-pdo-mysql=mysqlnd \
    --with-sodium=/usr/local \
    --with-xsl=/usr/local \
    --with-zip \
    --with-zlib \
    --enable-phar \
    --with-layout=GNU \
    || {
    echo -e "${RED}ERROR: PHP configure failed${NC}"
    echo "Check config.log for details"
    cat config.log | tail -100
    exit 1
}

echo ""
echo "Building PHP (this takes a while)..."
gmake -j${PARALLEL_JOBS} || gmake

echo ""
echo "Installing PHP..."
gmake install

# Verify the static PHP binary was built
STATIC_PHP="${PHP_INSTALL_DIR}/bin/php"
if [ ! -f "${STATIC_PHP}" ]; then
    STATIC_PHP="${PHP_SRC_DIR}/sapi/cli/php"
fi

if [ ! -f "${STATIC_PHP}" ]; then
    echo -e "${RED}ERROR: Failed to build static PHP binary${NC}"
    exit 1
fi

# Check if binary is static
echo ""
echo "Checking binary linking..."
file "${STATIC_PHP}"
ldd "${STATIC_PHP}" 2>/dev/null || echo "(statically linked or no dynamic dependencies)"

echo -e "${GREEN}✓ Static PHP built successfully${NC}"
echo ""

# Display PHP info
"${STATIC_PHP}" -v
echo ""
"${STATIC_PHP}" -m
echo ""

# Create the final self-contained binary by combining PHP + PHAR
echo -e "${YELLOW}Creating self-contained OpenEMR binary...${NC}"

FINAL_BINARY="${BUILD_DIR}/openemr-${OPENEMR_TAG}-freebsd-${ARCH}"

# Method 1: Use PHP's built-in phar embedding (if micro SAPI available)
# Method 2: Create a self-extracting binary
# Method 3: Simple concatenation with stub

# Create a launcher stub that extracts and runs the PHAR
cat > "${BUILD_DIR}/stub.c" << 'STUBCODE'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    const char *php_path = "/usr/local/bin/php";

    // argv must have at least argv[0] and a NULL terminator by C standard
    if (argc < 1 || argv[0] == NULL) {
        fprintf(stderr, "Invalid argv[0]\n");
        return 1;
    }

    char **new_argv = malloc((size_t)(argc + 2) * sizeof(char *));
    if (new_argv == NULL) {
        perror("malloc failed");
        return 1;
    }

    // new argv: php_path, self (binary containing PHAR), then any extra args
    new_argv[0] = (char *)php_path; // cast away const for execv's prototype
    new_argv[1] = argv[0];

    for (int i = 1; i < argc; i++) {
        new_argv[i + 1] = argv[i];
    }

    new_argv[argc + 1] = NULL;

    execv(php_path, new_argv);

    // If we got here, execv failed
    perror("execv failed");
    free(new_argv);
    return 1;
}
STUBCODE

# For FreeBSD, we'll create a distribution package with the static PHP + PHAR
DIST_DIR="${BUILD_DIR}/openemr-${OPENEMR_TAG}-freebsd-${ARCH}"
mkdir -p "${DIST_DIR}"
mkdir -p "${DIST_DIR}/lib"

# Copy the PHP binary
cp "${STATIC_PHP}" "${DIST_DIR}/php"
chmod +x "${DIST_DIR}/php"

# Copy the PHAR
cp "${BUILD_DIR}/openemr.phar" "${DIST_DIR}/openemr.phar"

# Bundle required shared libraries for portability
echo "Bundling required shared libraries..."
# Use ldd to find all required libraries and copy them (POSIX-compatible)
ldd "${DIST_DIR}/php" 2>/dev/null | grep "=>" | awk '{print $3}' | while read lib; do
    if [ -f "$lib" ]; then
        case "$lib" in
            /usr/local/*)
                cp "$lib" "${DIST_DIR}/lib/" 2>/dev/null && echo "  Bundled: $(basename $lib)"
                ;;
        esac
    fi
done

# Also explicitly copy common required libraries
for lib in libiconv.so.2 libintl.so.8 libpng16.so.16 libfreetype.so.6 libjpeg.so.8 libwebp.so.7 libxml2.so.2 libssl.so.* libcrypto.so.* libsqlite3.so.* libz.so.*; do
    if [ -f "/usr/local/lib/$lib" ]; then
        cp "/usr/local/lib/$lib" "${DIST_DIR}/lib/" 2>/dev/null
    fi
done
# Copy any matching libraries with glob
cp /usr/local/lib/libiconv.so* "${DIST_DIR}/lib/" 2>/dev/null || true
cp /usr/local/lib/libintl.so* "${DIST_DIR}/lib/" 2>/dev/null || true
cp /usr/local/lib/libpng*.so* "${DIST_DIR}/lib/" 2>/dev/null || true
cp /usr/local/lib/libfreetype.so* "${DIST_DIR}/lib/" 2>/dev/null || true
cp /usr/local/lib/libjpeg.so* "${DIST_DIR}/lib/" 2>/dev/null || true
cp /usr/local/lib/libwebp.so* "${DIST_DIR}/lib/" 2>/dev/null || true
echo "✓ Libraries bundled"

# Create launcher script that sets up library path and runs PHP
cat > "${DIST_DIR}/openemr" << 'LAUNCHER'
#!/bin/sh
# OpenEMR launcher script for FreeBSD
# Sets up library path to use bundled libraries

SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"

# Add bundled libraries to library path
export LD_LIBRARY_PATH="\${SCRIPT_DIR}/lib:\${LD_LIBRARY_PATH}"

exec "\${SCRIPT_DIR}/php" "\${SCRIPT_DIR}/openemr.phar" "\$@"
LAUNCHER
chmod +x "${DIST_DIR}/openemr"

# Create README
cat > "${DIST_DIR}/README.txt" << README
OpenEMR ${OPENEMR_TAG} for FreeBSD (${ARCH})
============================================

This is a self-contained OpenEMR distribution with a PHP binary and bundled libraries.
No system PHP installation is required.

Contents:
- openemr      - Main launcher script (use this to run OpenEMR)
- php          - PHP ${PHP_VERSION} binary
- openemr.phar - OpenEMR application archive
- lib/         - Bundled shared libraries

Usage:
  ./openemr [options]

The PHP binary includes these extensions:
bcmath, calendar, exif, gd, gettext, iconv, intl, mbstring, 
mysqli, openssl, pcntl, pdo, pdo_mysql, phar, soap, 
sockets, sodium, zip, zlib

For more information, visit: https://www.open-emr.org/
README

echo -e "${GREEN}✓ Distribution package created${NC}"
echo ""
echo "Contents:"
ls -la "${DIST_DIR}/"
echo ""

# Create tarball
cd "${BUILD_DIR}"
tar -czf "openemr-${OPENEMR_TAG}-freebsd-${ARCH}.tar.gz" "openemr-${OPENEMR_TAG}-freebsd-${ARCH}"

# Also keep standalone files
cp "${BUILD_DIR}/openemr.phar" "${BUILD_DIR}/openemr-${OPENEMR_TAG}.phar"

echo -e "${GREEN}✓ FreeBSD distribution package created${NC}"
echo ""
echo "Distribution contents:"
ls -la "${DIST_DIR}/"
echo ""
echo "Package: openemr-${OPENEMR_TAG}-freebsd-${ARCH}.tar.gz"

# Copy files to shared directory if available (for host retrieval)
if [ -d "/mnt/shared" ]; then
    echo ""
    echo "Copying build artifacts to shared directory..."
    cp "${BUILD_DIR}/openemr-${OPENEMR_TAG}-freebsd-${ARCH}.tar.gz" /mnt/shared/ 2>/dev/null && echo "  - Copied tarball"
    cp "${BUILD_DIR}/openemr-${OPENEMR_TAG}.phar" /mnt/shared/ 2>/dev/null && echo "  - Copied PHAR"
    cp "${DIST_DIR}/php" /mnt/shared/php-cli-${OPENEMR_TAG}-freebsd-${ARCH} 2>/dev/null && echo "  - Copied PHP binary"
    echo "✓ Files copied to /mnt/shared"
fi

echo ""
echo "=== BUILD FINISHED SUCCESSFULLY ==="
echo -e "${GREEN}✓ Build complete!${NC}"
echo ""
echo "Output files in ${BUILD_DIR}:"
ls -la "${BUILD_DIR}/"*.phar "${BUILD_DIR}/"openemr-* 2>/dev/null || ls -la "${BUILD_DIR}/"
FREEBUILD

chmod +x "${BUILD_DIR}/freebsd-build.sh"

echo -e "${GREEN}✓ Build script prepared${NC}"
echo ""

# Step 3: Set up QEMU and run FreeBSD VM
echo -e "${YELLOW}Step 3/6: Starting FreeBSD VM with QEMU...${NC}"
echo "This will start a FreeBSD virtual machine and automate the build process."
echo ""

# Create a shared directory for file transfer using virtio-9p
SHARED_DIR="${TMP_DIR}/shared"
mkdir -p "${SHARED_DIR}"

# Copy build script and environment variables to shared directory
echo "DEBUG: BUILD_DIR=${BUILD_DIR}"
echo "DEBUG: SHARED_DIR=${SHARED_DIR}"
echo "DEBUG: Checking if freebsd-build.sh exists in BUILD_DIR..."
ls -la "${BUILD_DIR}/freebsd-build.sh" || echo "ERROR: freebsd-build.sh not found in BUILD_DIR!"
cp "${BUILD_DIR}/freebsd-build.sh" "${SHARED_DIR}/"
echo "DEBUG: Checking if freebsd-build.sh exists in SHARED_DIR after copy..."
ls -la "${SHARED_DIR}/freebsd-build.sh" || echo "ERROR: freebsd-build.sh not found in SHARED_DIR!"

# Create environment file for the build script
cat > "${SHARED_DIR}/build-env.sh" << ENVFILE
export OPENEMR_TAG="${OPENEMR_TAG}"
export FREEBSD_VERSION="${FREEBSD_VERSION}"
export ARCH="${FREEBSD_ARCH}"
export PHP_VERSION="${PHP_VERSION}"
export PARALLEL_JOBS="${PARALLEL_JOBS}"
export FREEBSD_PHP_PKG="${FREEBSD_PHP_PKG}"
export FREEBSD_PHP_EXTENSIONS_PKG="${FREEBSD_PHP_EXTENSIONS_PKG}"
export FREEBSD_PHP_COMPOSER_PKG="${FREEBSD_PHP_COMPOSER_PKG}"
export FREEBSD_PHP_ZLIB_PKG="${FREEBSD_PHP_ZLIB_PKG}"
export FREEBSD_NODE_PKG="${FREEBSD_NODE_PKG}"
export FREEBSD_NPM_PKG="${FREEBSD_NPM_PKG}"
ENVFILE

# For Apple Silicon, use HVF acceleration
if [ "${ARCH}" = "arm64" ]; then
    QEMU_CMD="qemu-system-aarch64 -m ${VM_RAM_GB}G -cpu host -M virt,accel=hvf"
    # Try to find UEFI firmware
    UEFI_FIRMWARE=""
    if [ -f "/opt/homebrew/share/qemu/edk2-aarch64-code.fd" ]; then
        UEFI_FIRMWARE="/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
    elif [ -f "/usr/local/share/qemu/edk2-aarch64-code.fd" ]; then
        UEFI_FIRMWARE="/usr/local/share/qemu/edk2-aarch64-code.fd"
    fi
    
    if [ -n "${UEFI_FIRMWARE}" ]; then
        QEMU_CMD="${QEMU_CMD} -bios ${UEFI_FIRMWARE}"
    else
        echo -e "${YELLOW}Warning: UEFI firmware not found. Trying without -bios flag.${NC}"
    fi
else
    QEMU_CMD="qemu-system-x86_64 -m ${VM_RAM_GB}G -accel hvf"
fi

# Find an available port for HTTP download (VM to host file transfer)
VM_HTTP_PORT=8888
while lsof -Pi :${VM_HTTP_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; do
    VM_HTTP_PORT=$((VM_HTTP_PORT + 1))
    if [ ${VM_HTTP_PORT} -gt 8900 ]; then
        echo -e "${RED}ERROR: Could not find available port for VM HTTP server${NC}"
        exit 1
    fi
done
export VM_HTTP_PORT
echo "VM HTTP port (for downloading artifacts): ${VM_HTTP_PORT}"

# Set up QEMU with virtio-9p for file sharing and port forwarding for HTTP download
QEMU_CMD="${QEMU_CMD} -drive if=virtio,file=${FREEBSD_IMAGE},id=hd0"
QEMU_CMD="${QEMU_CMD} -device virtio-net,netdev=net0"
# Add port forwarding: host:VM_HTTP_PORT -> guest:8080 for downloading build artifacts
QEMU_CMD="${QEMU_CMD} -netdev user,id=net0,hostfwd=tcp::${VM_HTTP_PORT}-:8080"
QEMU_CMD="${QEMU_CMD} -fsdev local,id=fsdev0,path=${SHARED_DIR},security_model=none"
QEMU_CMD="${QEMU_CMD} -device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=shared"
# Find an available port for serial console
SERIAL_PORT=4444
while lsof -Pi :${SERIAL_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; do
    SERIAL_PORT=$((SERIAL_PORT + 1))
    if [ ${SERIAL_PORT} -gt 4450 ]; then
        echo -e "${RED}ERROR: Could not find available port for serial console${NC}"
        exit 1
    fi
done

# Export SERIAL_PORT so expect scripts can access it
export SERIAL_PORT

QEMU_CMD="${QEMU_CMD} -serial telnet::${SERIAL_PORT},server,nowait -display none"

echo "Starting QEMU VM in background..."
echo ""

# Start QEMU in background and capture PID
QEMU_LOG="${TMP_DIR}/qemu.log"
eval "${QEMU_CMD}" > "${QEMU_LOG}" 2>&1 &
QEMU_PID=$!

# Wait a moment for QEMU to start
sleep 3

# Check if QEMU is running
if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
    echo -e "${RED}ERROR: QEMU VM failed to start${NC}"
    echo "QEMU log:"
    cat "${QEMU_LOG}"
    exit 1
fi
echo -e "${GREEN}✓ QEMU VM started (PID: ${QEMU_PID})${NC}"
echo ""

# Note: QEMU cleanup is handled by the main cleanup() function via trap

# Step 4: Wait for VM to boot and configure
echo -e "${YELLOW}Step 4/6: Waiting for FreeBSD VM to boot...${NC}"
echo "This may take 1-2 minutes for the VM to fully boot."
echo ""

# Create a script to automate VM setup via serial console
SETUP_SCRIPT="${TMP_DIR}/vm-setup.exp"

# Check if expect is available
if ! command -v expect >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: 'expect' not found. Installing via Homebrew...${NC}"
    if command -v brew >/dev/null 2>&1; then
        brew install expect || {
            echo -e "${RED}ERROR: Failed to install expect. Please install manually: brew install expect${NC}"
            exit 1
        }
    else
        echo -e "${RED}ERROR: 'expect' is required for automation. Install with: brew install expect${NC}"
        exit 1
    fi
fi

# Check if telnet is available for serial console (QEMU uses telnet protocol)
if ! command -v telnet >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing telnet via Homebrew for serial console access...${NC}"
    if command -v brew >/dev/null 2>&1; then
        brew install telnet || {
            echo -e "${RED}ERROR: Failed to install telnet. Please install manually: brew install telnet${NC}"
            exit 1
        }
    else
        echo -e "${RED}ERROR: telnet is required for QEMU serial console access${NC}"
        echo "Install with: brew install telnet"
        exit 1
    fi
fi

# Create combined expect script for setup AND build (single session, no exit)
cat > "${SETUP_SCRIPT}" << 'EXPECTSCRIPT'
#!/usr/bin/expect -f
set timeout 7200
log_user 1
spawn telnet localhost $env(SERIAL_PORT)

expect {
    "login:" {
        send "root\r"
        exp_continue
    }
    "Password:" {
        send "\r"
        exp_continue
    }
    "# " {
        send "echo 'VM is ready'\r"
    }
    timeout {
        puts "Timeout waiting for VM to boot"
        exit 1
    }
}

# Wait a bit for system to be ready
sleep 2

# Grow the filesystem to use all available disk space (we resized the disk on the host)
puts "Growing filesystem to use full disk space...\n"
send "gpart recover vtbd0\r"
expect "# "
send "gpart resize -i 3 vtbd0\r"
expect "# "
send "growfs -y /dev/vtbd0p3\r"
expect "# "
send "df -h /\r"
expect "# "

# Set up 9p shared directory for artifact retrieval
puts "Setting up 9p shared directory for artifact retrieval...\n"
send "kldload -n virtio 2>/dev/null || true\r"
expect "# "
send "kldload -n p9fs 2>/dev/null || true\r"
expect "# "
send "mkdir -p /mnt/shared\r"
expect "# "
# Try mount with different syntaxes (FreeBSD 9p mount variations)
send "mount -t p9fs shared /mnt/shared 2>/dev/null || mount_9p shared /mnt/shared 2>/dev/null || mount -t virtfs shared /mnt/shared 2>/dev/null && echo '9p mount successful' || echo '9p mount failed (will use HTTP fallback)'\r"
expect "# "
# Verify mount
send "ls -la /mnt/shared/ 2>/dev/null || echo 'shared directory not accessible'\r"
expect "# "

# Download build files via HTTP (more reliable than 9p for initial transfer)
puts "Downloading build files via HTTP (port $env(HTTP_PORT))...\n"
send "mkdir -p /build\r"
expect "# "
send "cd /build\r"
expect "# "
send "fetch -o freebsd-build.sh http://10.0.2.2:$env(HTTP_PORT)/freebsd-build.sh\r"
expect "# "
send "fetch -o build-env.sh http://10.0.2.2:$env(HTTP_PORT)/build-env.sh\r"
expect "# "
send "chmod +x freebsd-build.sh\r"
expect "# "

# Now run the build in the same session (don't exit!)
puts "\nStarting build process...\n"
send "cd /build && . ./build-env.sh && ./freebsd-build.sh\r"
expect {
    "# " {
        # Build command started, now stream output
    }
    timeout {
        # Command may have started, continue streaming
    }
}

# Stream all build output in real-time and handle pkg bootstrap prompts
# With log_user 1, expect automatically displays all output
set build_success 0
set build_failed 0

# Use shorter timeout for responsive output streaming
set timeout 30

while {1} {
    expect {
        -re "Do you want to fetch and install it now" {
            # pkg bootstrap prompt - answer yes
            send "y\r"
            exp_continue
        }
        -re "y/N" {
            # Yes/No prompt pattern
            send "y\r"
            exp_continue
        }
        "BUILD FINISHED SUCCESSFULLY" {
            # Build succeeded - main marker
            puts "\n*** Detected BUILD FINISHED SUCCESSFULLY marker ***\n"
            set build_success 1
            exp_continue
        }
        "Build complete!" {
            # Build succeeded - secondary marker
            set build_success 1
            exp_continue
        }
        -re "ERROR:.*Cannot continue" {
            # Critical error - build failed
            set build_failed 1
            exp_continue
        }
        -re "root@freebsd:/build #" {
            # Shell prompt appeared after build - check if success
            puts "\n*** Detected shell prompt ***\n"
            if {$build_success} {
                puts "\n\n=== Build completed successfully! ===\n"
                puts "Starting HTTP server for artifact download...\n"
                # Start HTTP server in background on the build directory
                send "cd /build && python3 -m http.server 8080 > /dev/null 2>&1 &\r"
                sleep 2
                puts "HTTP server started on port 8080\n"
                break
            } else {
                # Wait a bit and check if more output is coming
                # (prompt might appear during script execution)
                sleep 2
                exp_continue
            }
        }
        -re "root@freebsd:\[^\r\n\]*# $" {
            # Generic shell prompt at end of line
            puts "\n*** Detected generic shell prompt ***\n"
            if {$build_success} {
                puts "\n\n=== Build completed successfully! ===\n"
                puts "Starting HTTP server for artifact download...\n"
                # Start HTTP server in background on the build directory
                send "cd /build && python3 -m http.server 8080 > /dev/null 2>&1 &\r"
                sleep 2
                puts "HTTP server started on port 8080\n"
                break
            }
            # Not yet successful, wait for more
            exp_continue
        }
        eof {
            # Connection closed unexpectedly
            puts "\n*** EOF detected ***\n"
            if {!$build_success} {
                puts "\n\nConnection closed unexpectedly (EOF) - build may have failed!\n"
                set build_failed 1
            } else {
                puts "\n\n=== Build completed (EOF after success) ===\n"
            }
            break
        }
        timeout {
            # Short timeout - just continue waiting
            # The log_user 1 already displays output as it arrives
            exp_continue
        }
    }
}

# Exit with appropriate code
if {$build_failed} {
    exit 1
} else {
    exit 0
}
EXPECTSCRIPT

chmod +x "${SETUP_SCRIPT}"

echo "Waiting for VM to be ready (this may take 1-2 minutes)..."
echo ""

# Wait for VM to boot (check if we can connect to serial console)
BOOT_TIMEOUT=120
BOOT_ELAPSED=0
BOOT_INTERVAL=5

# Try to detect if VM console is accessible
VM_READY=false
if command -v nc >/dev/null 2>&1; then
    # Use netcat if available
    while [ ${BOOT_ELAPSED} -lt ${BOOT_TIMEOUT} ]; do
        if echo "" | nc -w 1 localhost ${SERIAL_PORT} >/dev/null 2>&1; then
            VM_READY=true
            break
        fi
        echo -n "."
        sleep ${BOOT_INTERVAL}
        BOOT_ELAPSED=$((BOOT_ELAPSED + BOOT_INTERVAL))
    done
else
    # Fallback: just wait a fixed time for VM to boot
    echo -e "${YELLOW}Note: netcat not found, waiting fixed time for VM to boot...${NC}"
    sleep 30
    VM_READY=true
fi

if [ "${VM_READY}" = "true" ]; then
    echo ""
    echo -e "${GREEN}✓ VM console should be ready${NC}"
else
    echo ""
    echo -e "${YELLOW}Warning: Could not verify VM console, but continuing...${NC}"
fi

echo ""
echo ""

# Step 5: Automate VM setup and build
echo -e "${YELLOW}Step 5/6: Automating VM setup and build process...${NC}"
echo "This will:"
echo "  1. Mount the shared directory (or download files via HTTP)"
echo "  2. Run the build script automatically via console"
echo ""
echo -e "${BLUE}Note: The build process will take 1-2 hours.${NC}"
echo -e "${BLUE}All build output will be streamed to this terminal in real-time.${NC}"
echo -e "${BLUE}You can also monitor by connecting to the VM console: telnet localhost ${SERIAL_PORT}${NC}"
echo ""

# Start HTTP server with dynamic port allocation (avoids conflicts)
# Note: HTTP_SERVER_PID is initialized at script start and cleaned up by trap
HTTP_PORT=8000
while lsof -Pi :${HTTP_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; do
    HTTP_PORT=$((HTTP_PORT + 1))
    if [ ${HTTP_PORT} -gt 8100 ]; then
        echo -e "${RED}ERROR: Could not find available port for HTTP server${NC}"
        exit 1
    fi
done
export HTTP_PORT

echo "DEBUG: Files in SHARED_DIR before starting HTTP server:"
ls -la "${SHARED_DIR}/"
if command -v python3 >/dev/null 2>&1; then
    cd "${SHARED_DIR}"
    python3 -m http.server ${HTTP_PORT} >/dev/null 2>&1 &
    HTTP_SERVER_PID=$!
    cd - >/dev/null
    echo "Started HTTP server on port ${HTTP_PORT} for file transfer"
fi

# Run the combined setup and build script (single session, no exit)
echo "Starting VM setup and build (all output will stream below)..."
echo ""
"${SETUP_SCRIPT}" 2>&1 || {
    echo ""
    echo -e "${RED}ERROR: Build failed in VM${NC}"
    echo "You can connect to the VM console to debug: telnet localhost ${SERIAL_PORT}"
    exit 1
}
echo ""
echo -e "${GREEN}✓ Build completed in VM${NC}"

# Stop HTTP server used for sending files TO the VM (build is complete)
if [ -n "${HTTP_SERVER_PID}" ] && kill -0 "${HTTP_SERVER_PID}" 2>/dev/null; then
    kill "${HTTP_SERVER_PID}" 2>/dev/null || true
    echo "Stopped file transfer HTTP server"
fi

echo ""

# Step 6: Download build artifacts from VM using HTTP
echo -e "${YELLOW}Step 6/6: Downloading build artifacts from VM via HTTP...${NC}"

# Create dist directory
mkdir -p "${SCRIPT_DIR}/dist"

# HTTP server was already started in the VM before the expect script exited
# It's running on VM port 8080, forwarded to host port VM_HTTP_PORT
echo "HTTP server should already be running in VM (started before expect script exited)"
echo "Waiting for HTTP server to be ready..."
sleep 3

# Download files from VM via port forwarding
echo ""
echo "Downloading build artifacts from http://localhost:${VM_HTTP_PORT}/..."
echo ""

BINARY_COUNT=0

# Download the tarball
TARBALL_NAME="openemr-${OPENEMR_TAG}-freebsd-${FREEBSD_ARCH}.tar.gz"
echo "Downloading ${TARBALL_NAME}..."
if curl -sf --connect-timeout 10 --max-time 600 \
    "http://localhost:${VM_HTTP_PORT}/${TARBALL_NAME}" \
    -o "${SCRIPT_DIR}/dist/${TARBALL_NAME}"; then
    BINARY_COUNT=$((BINARY_COUNT + 1))
    echo -e "${GREEN}✓ Downloaded ${TARBALL_NAME}${NC}"
else
    echo -e "${YELLOW}Warning: Could not download ${TARBALL_NAME}${NC}"
fi

# Download the PHAR
PHAR_NAME="openemr-${OPENEMR_TAG}.phar"
echo "Downloading ${PHAR_NAME}..."
if curl -sf --connect-timeout 10 --max-time 1200 \
    "http://localhost:${VM_HTTP_PORT}/${PHAR_NAME}" \
    -o "${SCRIPT_DIR}/dist/${PHAR_NAME}"; then
    BINARY_COUNT=$((BINARY_COUNT + 1))
    echo -e "${GREEN}✓ Downloaded ${PHAR_NAME}${NC}"
else
    # Try alternate name
    echo "Trying alternate PHAR name..."
    if curl -sf --connect-timeout 10 --max-time 1200 \
        "http://localhost:${VM_HTTP_PORT}/openemr.phar" \
        -o "${SCRIPT_DIR}/dist/openemr.phar"; then
        BINARY_COUNT=$((BINARY_COUNT + 1))
        echo -e "${GREEN}✓ Downloaded openemr.phar${NC}"
    else
        echo -e "${YELLOW}Warning: Could not download PHAR${NC}"
    fi
fi

# Download the PHP binary from the distribution directory
PHP_BINARY_PATH="${OPENEMR_TAG}-freebsd-${FREEBSD_ARCH}/php"
echo "Downloading PHP binary..."
if curl -sf --connect-timeout 10 --max-time 300 \
    "http://localhost:${VM_HTTP_PORT}/openemr-${PHP_BINARY_PATH}" \
    -o "${SCRIPT_DIR}/dist/php"; then
    chmod +x "${SCRIPT_DIR}/dist/php"
    BINARY_COUNT=$((BINARY_COUNT + 1))
    echo -e "${GREEN}✓ Downloaded PHP binary${NC}"
else
    # Try alternate location
    if curl -sf --connect-timeout 10 --max-time 300 \
        "http://localhost:${VM_HTTP_PORT}/php-static/bin/php" \
        -o "${SCRIPT_DIR}/dist/php"; then
        chmod +x "${SCRIPT_DIR}/dist/php"
        BINARY_COUNT=$((BINARY_COUNT + 1))
        echo -e "${GREEN}✓ Downloaded PHP binary${NC}"
    else
        echo -e "${YELLOW}Warning: Could not download PHP binary${NC}"
    fi
fi

# Download the launcher script
echo "Downloading launcher script..."
if curl -sf --connect-timeout 10 --max-time 30 \
    "http://localhost:${VM_HTTP_PORT}/openemr-${OPENEMR_TAG}-freebsd-${FREEBSD_ARCH}/openemr" \
    -o "${SCRIPT_DIR}/dist/openemr"; then
    chmod +x "${SCRIPT_DIR}/dist/openemr"
    BINARY_COUNT=$((BINARY_COUNT + 1))
    echo -e "${GREEN}✓ Downloaded launcher script${NC}"
fi

# If HTTP download didn't work, check 9p shared directory as fallback
if [ ${BINARY_COUNT} -eq 0 ]; then
    echo ""
    echo "HTTP download failed. Checking 9p shared directory as fallback..."
    
    for f in "${SHARED_DIR}/"*; do
        if [ -f "$f" ]; then
            cp "$f" "${SCRIPT_DIR}/dist/" 2>/dev/null && BINARY_COUNT=$((BINARY_COUNT + 1))
        fi
    done
    
    if [ ${BINARY_COUNT} -gt 0 ]; then
        echo -e "${GREEN}✓ Found ${BINARY_COUNT} files in shared directory${NC}"
    fi
fi

if [ ${BINARY_COUNT} -eq 0 ]; then
    echo -e "${YELLOW}Warning: No build artifacts found${NC}"
    echo "The build may have completed but files weren't copied."
    echo "You can manually copy files from the VM console:"
    echo "  telnet localhost ${SERIAL_PORT}"
    echo "  Files should be in /mnt/shared or /build"
else
    echo ""
    echo -e "${GREEN}✓ All build artifacts copied successfully${NC}"
    echo ""
    echo "Output files in ${SCRIPT_DIR}/dist/:"
    ls -lh "${SCRIPT_DIR}/dist/" 2>/dev/null
fi

echo ""
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "Binary location: ${SCRIPT_DIR}/openemr-${OPENEMR_TAG}-freebsd-${FREEBSD_ARCH}"
echo ""
echo "To run OpenEMR web server:"
echo "  ./run-web-server.sh [port]"
echo ""
echo "Example:"
echo "  ./run-web-server.sh 8080"
echo ""

