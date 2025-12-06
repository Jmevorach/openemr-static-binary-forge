#!/usr/bin/env bash
# ==============================================================================
# OpenEMR FreeBSD VM Runner for macOS
# ==============================================================================
# This script boots a FreeBSD QEMU VM, copies OpenEMR artifacts into it,
# starts a web server, and makes it accessible from the macOS host.
#
# Usage:
#   ./run-freebsd-vm.sh [options]
#
# Options:
#   -p, --port PORT      Host port to access OpenEMR (default: 8080)
#   -v, --version VER    FreeBSD version (default: 15.0)
#   -m, --memory MEM     VM memory in GB (default: 4)
#   -c, --cpus CPUS      Number of CPU cores (default: 2)
#   -h, --help           Show this help message
#
# Note: A fresh VM image is always downloaded to a temporary directory
#       to prevent corruption issues from previous runs.
#
# Example:
#   ./run-freebsd-vm.sh -p 8080
#   ./run-freebsd-vm.sh -v 14.2 -p 9000 -m 8 -c 4
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Default arguments
HOST_PORT="8080"
FREEBSD_VERSION="15.0"
VM_MEMORY="4"
VM_CPUS="2"
FORCE_FRESH="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            HOST_PORT="$2"
            shift 2
            ;;
        -v|--version)
            FREEBSD_VERSION="$2"
            shift 2
            ;;
        -m|--memory)
            VM_MEMORY="$2"
            shift 2
            ;;
        -c|--cpus)
            VM_CPUS="$2"
            shift 2
            ;;
        --fresh)
            FORCE_FRESH="true"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -p, --port PORT      Host port to access OpenEMR (default: 8080)"
            echo "  -v, --version VER    FreeBSD version (default: 15.0)"
            echo "  -m, --memory MEM     VM memory in GB (default: 4)"
            echo "  -c, --cpus CPUS      Number of CPU cores (default: 2)"
            echo "  --fresh              Force fresh VM image download"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Example:"
            echo "  $0 -p 8080"
            echo "  $0 -v 14.2 -p 9000 -m 8 -c 4"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Print banner
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}${BOLD}           OpenEMR FreeBSD VM Runner for macOS                            ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Configuration summary
echo -e "${BOLD}Configuration:${NC}"
echo -e "  FreeBSD Version: ${GREEN}${FREEBSD_VERSION}${NC}"
echo -e "  Host Port:       ${GREEN}${HOST_PORT}${NC}"
echo -e "  VM Memory:       ${GREEN}${VM_MEMORY}GB${NC}"
echo -e "  VM CPUs:         ${GREEN}${VM_CPUS}${NC}"
echo ""

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}ERROR: This script is designed for macOS only${NC}"
    exit 1
fi

# Check required tools
echo -e "${YELLOW}Checking requirements...${NC}"
MISSING_TOOLS=()
if ! command -v qemu-system-aarch64 >/dev/null 2>&1 && ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    MISSING_TOOLS+=("qemu")
fi
if ! command -v expect >/dev/null 2>&1; then
    MISSING_TOOLS+=("expect")
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo -e "${RED}ERROR: Missing required tools: ${MISSING_TOOLS[*]}${NC}"
    echo ""
    echo "Install missing tools:"
    for tool in "${MISSING_TOOLS[@]}"; do
        case "${tool}" in
            qemu)
                echo "  brew install qemu"
                ;;
            expect)
                echo "  brew install expect"
                ;;
        esac
    done
    exit 1
fi
echo -e "${GREEN}✓ All required tools are available${NC}"

# Check for build artifacts
DIST_DIR="${SCRIPT_DIR}/dist"
if [ ! -d "${DIST_DIR}" ]; then
    echo -e "${RED}ERROR: Build artifacts not found at ${DIST_DIR}${NC}"
    echo ""
    echo "Please run the build script first:"
    echo "  cd ${SCRIPT_DIR}"
    echo "  ./build-freebsd.sh"
    exit 1
fi

# Find the PHAR file
PHAR_FILE=$(find "${DIST_DIR}" -name "*.phar" -type f 2>/dev/null | head -1)
if [ -z "${PHAR_FILE}" ]; then
    echo -e "${RED}ERROR: No PHAR file found in ${DIST_DIR}${NC}"
    echo "Please run the build script first."
    exit 1
fi

# Find the PHP binary (could be named 'php' or 'php-cli-*')
PHP_BINARY=$(find "${DIST_DIR}" -name "php" -type f 2>/dev/null | head -1)
if [ -z "${PHP_BINARY}" ]; then
    PHP_BINARY=$(find "${DIST_DIR}" -name "php-cli-*" -type f 2>/dev/null | head -1)
fi
if [ -z "${PHP_BINARY}" ]; then
    echo -e "${RED}ERROR: No PHP binary found in ${DIST_DIR}${NC}"
    echo "Please run the build script first."
    exit 1
fi

echo -e "${GREEN}✓ Found build artifacts:${NC}"
echo "  PHAR:   $(basename "${PHAR_FILE}")"
echo "  PHP:    $(basename "${PHP_BINARY}")"
echo ""

# Determine architecture
ARCH=$(uname -m)
QEMU_SYSTEM_BIN=""
FREEBSD_ARCH=""
QEMU_MACHINE=""
UEFI_BIOS_PATH=""

if [ "${ARCH}" = "arm64" ]; then
    QEMU_SYSTEM_BIN="qemu-system-aarch64"
    FREEBSD_ARCH="aarch64"
    QEMU_MACHINE="virt,accel=hvf"
    # Check for UEFI firmware
    if [ -f "/opt/homebrew/share/qemu/edk2-aarch64-code.fd" ]; then
        UEFI_BIOS_PATH="/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
    elif [ -f "/usr/local/share/qemu/edk2-aarch64-code.fd" ]; then
        UEFI_BIOS_PATH="/usr/local/share/qemu/edk2-aarch64-code.fd"
    else
        echo -e "${RED}ERROR: UEFI firmware not found for aarch64${NC}"
        echo "Please ensure QEMU is installed via Homebrew."
        exit 1
    fi
elif [ "${ARCH}" = "x86_64" ]; then
    QEMU_SYSTEM_BIN="qemu-system-x86_64"
    FREEBSD_ARCH="amd64"
    QEMU_MACHINE="q35,accel=hvf"
else
    echo -e "${RED}ERROR: Unsupported architecture: ${ARCH}${NC}"
    exit 1
fi

# Check if QEMU binary exists
if ! command -v "${QEMU_SYSTEM_BIN}" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: QEMU binary '${QEMU_SYSTEM_BIN}' not found${NC}"
    echo "Please install QEMU: brew install qemu"
    exit 1
fi

# VM image configuration - always use a fresh temporary directory
# This prevents issues with corrupted images from previous runs
VM_TMP_DIR=$(mktemp -d)
echo "Using temporary VM directory: ${VM_TMP_DIR}"

# Determine the correct image name based on FreeBSD version and architecture
# FreeBSD 15.0+ uses "arm64-aarch64" format for ARM images
if [[ "${FREEBSD_ARCH}" == "aarch64" ]]; then
    VM_IMAGE_NAME="FreeBSD-${FREEBSD_VERSION}-RELEASE-arm64-aarch64-ufs.qcow2"
else
    VM_IMAGE_NAME="FreeBSD-${FREEBSD_VERSION}-RELEASE-${FREEBSD_ARCH}-ufs.qcow2"
fi
VM_IMAGE_PATH="${VM_TMP_DIR}/${VM_IMAGE_NAME}"

# FreeBSD download URL
FREEBSD_BASE_URL="https://download.freebsd.org/releases/VM-IMAGES/${FREEBSD_VERSION}-RELEASE/${FREEBSD_ARCH}/Latest"
VM_IMAGE_URL="${FREEBSD_BASE_URL}/${VM_IMAGE_NAME}.xz"

# Always download a fresh VM image to avoid corruption issues
echo -e "${YELLOW}Downloading fresh FreeBSD ${FREEBSD_VERSION} VM image...${NC}"
echo "URL: ${VM_IMAGE_URL}"

# Download compressed image
COMPRESSED_IMAGE="${VM_IMAGE_PATH}.xz"
if ! curl -L --progress-bar -o "${COMPRESSED_IMAGE}" "${VM_IMAGE_URL}"; then
    echo -e "${RED}ERROR: Failed to download FreeBSD image${NC}"
    echo "URL: ${VM_IMAGE_URL}"
    rm -rf "${VM_TMP_DIR}"
    exit 1
fi

# Decompress
echo -e "${YELLOW}Decompressing VM image...${NC}"
if ! xz -d -f "${COMPRESSED_IMAGE}"; then
    echo -e "${RED}ERROR: Failed to decompress VM image${NC}"
    rm -rf "${VM_TMP_DIR}"
    exit 1
fi

# Resize the disk image to 20GB (default is only ~6GB which isn't enough for OpenEMR extraction)
echo -e "${YELLOW}Resizing VM disk to 20GB for OpenEMR...${NC}"
if ! command -v qemu-img >/dev/null 2>&1; then
    echo -e "${RED}ERROR: qemu-img is required to resize the VM disk${NC}"
    echo "Please install QEMU: brew install qemu"
    rm -rf "${VM_TMP_DIR}"
    exit 1
fi
if ! qemu-img resize "${VM_IMAGE_PATH}" 20G; then
    echo -e "${RED}ERROR: Failed to resize VM disk${NC}"
    rm -rf "${VM_TMP_DIR}"
    exit 1
fi
echo -e "${GREEN}✓ VM disk resized to 20GB${NC}"

echo -e "${GREEN}✓ Fresh VM image ready${NC}"

# Shared directory for artifacts (serves as HTTP root)
SHARED_DIR=$(mktemp -d)
echo "Shared directory: ${SHARED_DIR}"

# Copy artifacts to shared directory with consistent names for HTTP download
cp "${PHAR_FILE}" "${SHARED_DIR}/openemr.phar"
cp "${PHP_BINARY}" "${SHARED_DIR}/php"
chmod +x "${SHARED_DIR}/php"

# Copy php.ini if it exists
if [ -f "${SCRIPT_DIR}/php.ini" ]; then
    cp "${SCRIPT_DIR}/php.ini" "${SHARED_DIR}/php.ini"
fi

# Copy router.php if it exists (for PHP built-in server)
if [ -f "${SCRIPT_DIR}/router.php" ]; then
    cp "${SCRIPT_DIR}/router.php" "${SHARED_DIR}/router.php"
    echo -e "${GREEN}✓ Router script copied to shared directory${NC}"
fi

# Copy the lib/ directory with bundled shared libraries
# Look for lib/ next to the PHP binary or in extracted distribution
PHP_DIR=$(dirname "${PHP_BINARY}")
LIB_DIR=""
if [ -d "${PHP_DIR}/lib" ]; then
    LIB_DIR="${PHP_DIR}/lib"
elif [ -d "${DIST_DIR}/openemr-"*"/lib" ]; then
    LIB_DIR=$(find "${DIST_DIR}" -type d -name "lib" -path "*/openemr-*" 2>/dev/null | head -1)
fi

if [ -n "${LIB_DIR}" ] && [ -d "${LIB_DIR}" ]; then
    echo "Copying bundled libraries from ${LIB_DIR}..."
    mkdir -p "${SHARED_DIR}/lib"
    cp -r "${LIB_DIR}"/* "${SHARED_DIR}/lib/"
    echo -e "${GREEN}✓ Bundled libraries copied${NC}"
else
    echo -e "${YELLOW}Warning: lib/ directory not found - PHP may fail if libraries are missing${NC}"
fi

echo -e "${GREEN}✓ Artifacts copied to shared directory${NC}"

# Create a startup script for the VM
cat > "${SHARED_DIR}/start-server.sh" << 'STARTUP_SCRIPT'
#!/bin/sh
# OpenEMR Server Startup Script for FreeBSD

set -e

echo "======================================"
echo "OpenEMR FreeBSD Server Setup"
echo "======================================"

# Configuration
SHARED_DIR="/mnt/shared"
OPENEMR_DIR="/build/openemr"
WEB_PORT=80

# Wait for shared directory to be mounted
echo "Waiting for shared directory..."
for i in $(seq 1 30); do
    if [ -d "${SHARED_DIR}" ] && [ -f "${SHARED_DIR}/php" ]; then
        echo "Shared directory found!"
        break
    fi
    sleep 1
done

if [ ! -f "${SHARED_DIR}/php" ]; then
    echo "ERROR: PHP binary not found in shared directory"
    exit 1
fi

# Find the PHAR file
PHAR_FILE=$(ls "${SHARED_DIR}"/*.phar 2>/dev/null | head -1)
if [ -z "${PHAR_FILE}" ]; then
    echo "ERROR: No PHAR file found in shared directory"
    exit 1
fi

echo "Found PHP binary: ${SHARED_DIR}/php"
echo "Found PHAR file: ${PHAR_FILE}"

# Create OpenEMR directory
mkdir -p "${OPENEMR_DIR}"
cd "${OPENEMR_DIR}"

# Extract the PHAR file
echo "Extracting OpenEMR from PHAR..."
"${SHARED_DIR}/php" -d phar.readonly=0 << 'EXTRACT_PHP'
<?php
$pharFile = getenv('PHAR_FILE') ?: glob('/mnt/shared/*.phar')[0] ?? null;
if (!$pharFile || !file_exists($pharFile)) {
    echo "ERROR: PHAR file not found\n";
    exit(1);
}

$destDir = '/build/openemr';
echo "Extracting $pharFile to $destDir...\n";

try {
    $phar = new Phar($pharFile);
    $phar->extractTo($destDir, null, true);
    echo "Extraction complete!\n";
} catch (Exception $e) {
    echo "ERROR: " . $e->getMessage() . "\n";
    exit(1);
}
EXTRACT_PHP

# Start the PHP built-in web server
echo ""
echo "======================================"
echo "Starting OpenEMR web server on port ${WEB_PORT}..."
echo "======================================"
echo ""

cd "${OPENEMR_DIR}"

# Use PHP's built-in server
"${SHARED_DIR}/php" -S 0.0.0.0:${WEB_PORT} -t . &

echo "SERVER_READY"
echo ""
echo "OpenEMR is now running!"
echo "Access it from your Mac at: http://localhost:<host_port>"
echo ""

# Keep the script running
while true; do
    sleep 60
done
STARTUP_SCRIPT
chmod +x "${SHARED_DIR}/start-server.sh"

# Find a free port for the serial console
find_free_port() {
    local port
    for port in $(seq 4440 4500); do
        if ! nc -z localhost $port 2>/dev/null; then
            echo $port
            return 0
        fi
    done
    echo "4444"
}
SERIAL_PORT=$(find_free_port)

# Global variables for cleanup
QEMU_PID=""
EXPECT_PID=""
HTTP_SERVER_PID=""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down...${NC}"
    
    # Kill HTTP server if running
    if [ -n "${HTTP_SERVER_PID}" ] && kill -0 "${HTTP_SERVER_PID}" 2>/dev/null; then
        kill "${HTTP_SERVER_PID}" 2>/dev/null || true
    fi
    
    # Kill expect if running
    if [ -n "${EXPECT_PID}" ] && kill -0 "${EXPECT_PID}" 2>/dev/null; then
        kill "${EXPECT_PID}" 2>/dev/null || true
    fi
    
    # Kill QEMU if running
    if [ -n "${QEMU_PID}" ] && kill -0 "${QEMU_PID}" 2>/dev/null; then
        kill "${QEMU_PID}" 2>/dev/null || true
        sleep 1
        kill -9 "${QEMU_PID}" 2>/dev/null || true
    fi
    
    # Remove shared directory
    if [ -d "${SHARED_DIR}" ]; then
        rm -rf "${SHARED_DIR}"
    fi
    
    # Remove VM temporary directory (contains the downloaded VM image)
    if [ -d "${VM_TMP_DIR}" ]; then
        rm -rf "${VM_TMP_DIR}"
    fi
    
    echo -e "${GREEN}Cleanup complete${NC}"
}
trap cleanup EXIT INT TERM

# Build QEMU command
QEMU_ARGS=(
    "${QEMU_SYSTEM_BIN}"
    "-m" "${VM_MEMORY}G"
    "-smp" "${VM_CPUS}"
    "-cpu" "host"
    "-M" "${QEMU_MACHINE}"
    "-drive" "if=virtio,file=${VM_IMAGE_PATH},id=hd0"
    "-device" "virtio-net-pci,netdev=net0"
    "-netdev" "user,id=net0,hostfwd=tcp::${HOST_PORT}-:80"
    "-fsdev" "local,id=fsdev0,path=${SHARED_DIR},security_model=none"
    "-device" "virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=shared"
    "-serial" "telnet::${SERIAL_PORT},server,nowait"
    "-display" "none"
    "-daemonize"
)

# Add UEFI for ARM64
if [ -n "${UEFI_BIOS_PATH}" ]; then
    QEMU_ARGS+=("-bios" "${UEFI_BIOS_PATH}")
fi

# Start QEMU
echo -e "${YELLOW}Starting QEMU VM...${NC}"
"${QEMU_ARGS[@]}"

# Get QEMU PID (find by port)
sleep 2
QEMU_PID=$(pgrep -f "telnet::${SERIAL_PORT}" 2>/dev/null | head -1 || true)
if [ -z "${QEMU_PID}" ]; then
    # Alternative: find by VM image
    QEMU_PID=$(pgrep -f "${VM_IMAGE_PATH}" 2>/dev/null | head -1 || true)
fi

if [ -z "${QEMU_PID}" ]; then
    echo -e "${RED}ERROR: Failed to start QEMU VM${NC}"
    exit 1
fi
echo -e "${GREEN}✓ QEMU started (PID: ${QEMU_PID})${NC}"

# Start HTTP server for file transfer (more reliable than 9p on FreeBSD)
HTTP_PORT=8001
while lsof -Pi :${HTTP_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; do
    HTTP_PORT=$((HTTP_PORT + 1))
    if [ ${HTTP_PORT} -gt 8100 ]; then
        echo -e "${RED}ERROR: Could not find available port for HTTP server${NC}"
        exit 1
    fi
done
export HTTP_PORT

echo "Starting HTTP server on port ${HTTP_PORT} for file transfer..."
cd "${SHARED_DIR}"
python3 -m http.server ${HTTP_PORT} >/dev/null 2>&1 &
HTTP_SERVER_PID=$!
cd - >/dev/null
sleep 1

if ! kill -0 "${HTTP_SERVER_PID}" 2>/dev/null; then
    echo -e "${RED}ERROR: Failed to start HTTP server${NC}"
    exit 1
fi
echo -e "${GREEN}✓ HTTP server started (PID: ${HTTP_SERVER_PID})${NC}"

# Wait for VM to boot and configure it via serial console
echo -e "${YELLOW}Waiting for VM to boot and configuring...${NC}"
echo "(This may take 30-60 seconds)"
echo ""

# Create expect script for VM interaction
EXPECT_SCRIPT=$(mktemp)
cat > "${EXPECT_SCRIPT}" << 'EXPECT_EOF'
#!/usr/bin/expect -f

set timeout 600
set serial_port [lindex $argv 0]
set host_port [lindex $argv 1]

log_user 1

# Connect to serial console
spawn telnet localhost $serial_port

expect {
    "Connection refused" {
        puts "ERROR: Could not connect to VM serial console"
        exit 1
    }
    "Connected to" {
        # Good, we're connected
    }
    timeout {
        puts "ERROR: Timeout connecting to VM"
        exit 1
    }
}

# Wait for login prompt
expect {
    "login:" {
        send "root\r"
    }
    timeout {
        puts "Timeout waiting for login prompt, trying to get one..."
        send "\r"
        expect "login:" { send "root\r" }
    }
}

# Wait for shell prompt
expect {
    "root@*:*#" { }
    "# " { }
    "Password:" {
        # FreeBSD root has no password by default
        send "\r"
        expect {
            "root@*:*#" { }
            "# " { }
        }
    }
    timeout {
        puts "ERROR: Timeout waiting for shell prompt"
        exit 1
    }
}

puts "\n=== VM logged in, growing filesystem and downloading files... ===\n"

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

# Get HTTP port from environment
set http_port $env(HTTP_PORT)

# Create build directory
send "mkdir -p /build\r"
expect "# "
send "cd /build\r"
expect "# "

# Download PHP binary via HTTP
puts "Downloading PHP binary..."
send "fetch -o php http://10.0.2.2:$http_port/php && chmod +x php && echo DOWNLOAD_PHP_OK\r"
expect {
    "DOWNLOAD_PHP_OK" {
        puts "PHP binary downloaded"
    }
    timeout {
        puts "ERROR: Failed to download PHP binary"
        exit 1
    }
}
expect "# "

# Download PHAR file via HTTP
puts "Downloading OpenEMR PHAR (this may take a minute)..."
send "fetch -o openemr.phar http://10.0.2.2:$http_port/openemr.phar && echo DOWNLOAD_PHAR_OK\r"
expect {
    "DOWNLOAD_PHAR_OK" {
        puts "PHAR file downloaded"
    }
    timeout {
        puts "ERROR: Failed to download PHAR file"
        exit 1
    }
}
expect "# "

# Download php.ini if available
send "fetch -o php.ini http://10.0.2.2:$http_port/php.ini 2>/dev/null || echo NO_PHP_INI\r"
expect "# "

# Download router.php if available
puts "Downloading router script..."
send "fetch -o router.php http://10.0.2.2:$http_port/router.php 2>/dev/null && echo ROUTER_DOWNLOADED || echo NO_ROUTER\r"
expect {
    "ROUTER_DOWNLOADED" {
        puts "Router script downloaded successfully"
    }
    "NO_ROUTER" {
        puts "No router script available, will create one"
    }
    timeout {
        puts "Timeout downloading router script"
    }
}
expect "# "

# Download bundled libraries
puts "Downloading bundled libraries..."
send "mkdir -p /build/lib\r"
expect "# "

# Get list of libraries from server and download each one
# First check if lib directory exists on server
send "fetch -q -o /tmp/liblist.html http://10.0.2.2:$http_port/lib/ 2>/dev/null && echo LIB_DIR_EXISTS || echo NO_LIB_DIR\r"
expect {
    "LIB_DIR_EXISTS" {
        puts "Downloading library files..."
    }
    "NO_LIB_DIR" {
        puts "No bundled libraries to download (may be OK)"
    }
    timeout {
        puts "Timeout checking for libraries"
    }
}
expect "# "

# Download all libraries from the lib directory
# Get the list of .so files and download each one
send "cd /build/lib && for lib in libiconv.so.2 libintl.so.8 libpng16.so.16 libfreetype.so.6 libjpeg.so.8 libxml2.so.16 libssl.so.12 libcrypto.so.12 libsqlite3.so.0 libonig.so.5 libsodium.so.26 libzip.so.5 libzstd.so.1 libicudata.so.76 libicui18n.so.76 libicuio.so.76 libicuuc.so.76 libwebp.so.7 libxslt.so.1 libexslt.so.0 libgcrypt.so.20 libgpg-error.so.0; do fetch -q -o \$lib http://10.0.2.2:$http_port/lib/\$lib 2>/dev/null && echo \"  Downloaded: \$lib\"; done && cd /build && echo LIB_DOWNLOAD_DONE\r"
set timeout 120
expect {
    "LIB_DOWNLOAD_DONE" {
        puts "Library download completed"
    }
    timeout {
        puts "Library download timed out (some may be missing)"
    }
}
set timeout 600
expect "# "

# Show downloaded files
send "ls -la /build/\r"
expect "# "
send "ls -la /build/lib/ 2>/dev/null || echo 'No lib directory'\r"
expect "# "

# Extract the PHAR (required for proper web serving)
puts "\n=== Extracting OpenEMR from PHAR... ===\n"
send "export LD_LIBRARY_PATH=/build/lib:\$LD_LIBRARY_PATH\r"
expect "# "

# Create extraction script
send "cat > /build/extract.php << 'EXTPHP'
<?php
ini_set('memory_limit', '1024M');
ini_set('max_execution_time', 0);
\$phar = new Phar('/build/openemr.phar');
\$phar->extractTo('/build/openemr', null, true);
echo \"EXTRACT_OK\\n\";
EXTPHP\r"
expect "# "

# Run extraction
puts "Extracting PHAR (this may take a minute)..."
send "./php -d memory_limit=1024M /build/extract.php\r"
set timeout 300
expect {
    "EXTRACT_OK" {
        puts "PHAR extraction completed"
    }
    timeout {
        puts "PHAR extraction timed out"
    }
}
set timeout 600
expect "# "

# Verify router script exists, create simple fallback if not
puts "\n=== Setting up router script for PHP built-in server... ===\n"
# Check if router.php exists using test command (avoids Tcl ! interpretation)
send "test -f /build/router.php && echo ROUTER_EXISTS || echo ROUTER_MISSING\r"
expect {
    "ROUTER_EXISTS" {
        puts "Router script found"
        expect "# "
    }
    "ROUTER_MISSING" {
        puts "Router script not found, creating fallback..."
        expect "# "
        # Create fallback router script
        send "cat > /build/router.php << 'ROUTER_EOF'
<?php
\$webRoot = '/build/openemr';
\$uri = parse_url(\$_SERVER['REQUEST_URI'], PHP_URL_PATH);
\$requestFile = \$webRoot . \$uri;
if (\$uri !== '/' && file_exists(\$requestFile) && !is_dir(\$requestFile)) {
    return false;
}
\$openemrEntryPoints = [
    \$webRoot . '/interface/main/main.php',
    \$webRoot . '/interface/main.php',
    \$webRoot . '/main.php',
    \$webRoot . '/index.php',
];
if (is_dir(\$webRoot)) {
    \$interfaceDir = \$webRoot . '/interface';
    if (is_dir(\$interfaceDir)) {
        if (is_dir(\$interfaceDir . '/main')) {
            \$openemrEntryPoints[] = \$interfaceDir . '/main/main.php';
            \$openemrEntryPoints[] = \$interfaceDir . '/main/index.php';
        }
        \$openemrEntryPoints[] = \$interfaceDir . '/main.php';
        \$openemrEntryPoints[] = \$interfaceDir . '/index.php';
    }
}
foreach (\$openemrEntryPoints as \$entryPoint) {
    if (file_exists(\$entryPoint)) {
        \$_SERVER['SCRIPT_NAME'] = \$entryPoint;
        \$_SERVER['PHP_SELF'] = \$entryPoint;
        \$_SERVER['DOCUMENT_ROOT'] = \$webRoot;
        require \$entryPoint;
        return;
    }
}
http_response_code(404);
echo \"OpenEMR entry point not found\\n\";
ROUTER_EOF
echo ROUTER_FALLBACK_CREATED\r"
        expect {
            "ROUTER_FALLBACK_CREATED" {
                puts "Router fallback script created successfully"
                expect "# "
            }
            timeout {
                puts "Warning: Router fallback creation may have timed out"
                expect "# "
            }
        }
    }
    timeout {
        puts "Warning: Router check timed out, will try to continue"
        expect "# "
    }
}
puts "Router script setup completed"

# Start the PHP web server with router
puts "\n=== Starting OpenEMR server... ===\n"
send "./php -c php.ini -d memory_limit=512M -S 0.0.0.0:80 -t /build/openemr /build/router.php 2>&1 &\r"
expect "# "

# Wait for server to start
send "sleep 3 && echo SERVER_READY\r"
expect {
    "SERVER_READY" {
        puts "\n"
        puts "=========================================="
        puts ""
        puts "  OpenEMR is now running on FreeBSD!"
        puts "  Access it at: http://localhost:$host_port"
        puts ""
        puts "=========================================="
        puts "\n"
        puts "Press Ctrl+C to stop the VM\n"
    }
    timeout {
        puts "\nTimeout waiting for server confirmation\n"
        puts "The server may still be starting..."
        puts "\nTry accessing http://localhost:$host_port\n"
    }
}

# Keep the connection open
expect {
    eof {
        puts "Connection closed"
        exit 0
    }
    timeout {
        # Keep waiting
        exp_continue
    }
}
EXPECT_EOF
chmod +x "${EXPECT_SCRIPT}"

# Run expect script
expect "${EXPECT_SCRIPT}" "${SERIAL_PORT}" "${HOST_PORT}" &
EXPECT_PID=$!

# Wait for expect to finish or user interrupt
wait "${EXPECT_PID}" 2>/dev/null || true
