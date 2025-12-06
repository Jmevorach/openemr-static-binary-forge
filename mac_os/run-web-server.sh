#!/usr/bin/env bash
# ==============================================================================
# OpenEMR Web Server Launcher
# ==============================================================================
# This script runs OpenEMR using ONLY the created executable binary.
# It uses the PHAR file saved during build and extracts it using the binary itself.
#
# Usage:
#   ./run-web-server.sh [port]
#
# Example:
#   ./run-web-server.sh 8080
#
# Default port: 8080
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Default port
PORT="${1:-8080}"

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}OpenEMR Web Server Launcher${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""

# Find the binary - this is the ONLY thing we need
BINARY_PATTERN="openemr-*-macos-*"
BINARY=$(find "${SCRIPT_DIR}" -maxdepth 1 -type f -name "${BINARY_PATTERN}" -perm +111 2>/dev/null | head -1)

if [ -z "${BINARY}" ] || [ ! -f "${BINARY}" ]; then
    echo -e "${RED}ERROR: Could not find OpenEMR binary${NC}"
    echo "Expected: ${SCRIPT_DIR}/${BINARY_PATTERN}"
    echo ""
    echo "Please build the binary first using: ./build-macos.sh"
    exit 1
fi

echo -e "${GREEN}Found binary: $(basename "${BINARY}")${NC}"
echo ""

# Find the standalone PHP CLI binary (required for PHAR extraction)
# Check both script directory and project root
PHP_CLI_PATTERN="php-cli-*-macos-*"
PHP_CLI_BINARY=$(find "${SCRIPT_DIR}" "${PROJECT_ROOT}" -maxdepth 1 -type f -name "${PHP_CLI_PATTERN}" -perm +111 2>/dev/null | head -1)

if [ -n "${PHP_CLI_BINARY}" ] && [ -f "${PHP_CLI_BINARY}" ]; then
    PHP_BIN="${PHP_CLI_BINARY}"
    echo -e "${GREEN}Found PHP CLI binary: $(basename "${PHP_CLI_BINARY}")${NC}"
    echo -e "${BLUE}Using PHP CLI binary for extraction (required for php.ini support)${NC}"
    echo ""
else
    echo -e "${RED}ERROR: PHP CLI binary not found${NC}"
    echo ""
    echo "The PHP CLI binary is required for PHAR extraction with proper memory limits."
    echo "Expected in: ${SCRIPT_DIR}/php-cli-*-macos-* or ${PROJECT_ROOT}/php-cli-*-macos-*"
    echo ""
    echo "Please rebuild using: ./build-macos.sh"
    echo "The build script should create both the combined binary and the PHP CLI binary."
    exit 1
fi

# Find the PHAR file that was saved during build
# Check both script directory and project root
PHAR_PATTERN="openemr-*.phar"
PHAR_FILE=$(find "${SCRIPT_DIR}" "${PROJECT_ROOT}" -maxdepth 1 -type f -name "${PHAR_PATTERN}" 2>/dev/null | head -1)

if [ -z "${PHAR_FILE}" ] || [ ! -f "${PHAR_FILE}" ]; then
    echo -e "${YELLOW}PHAR file not found in ${SCRIPT_DIR} or ${PROJECT_ROOT}${NC}"
    echo ""
    echo "The PHAR file should have been saved during the build process."
    echo "Please rebuild to save the PHAR file:"
    echo "  cd ${SCRIPT_DIR}"
    echo "  ./build-macos.sh"
    exit 1
fi

echo -e "${GREEN}Found PHAR file: $(basename "${PHAR_FILE}")${NC}"
echo ""

# Check for custom php.ini file
PHP_INI_FILE="${SCRIPT_DIR}/php.ini"
PHP_INI_FLAG=""
PHP_MEMORY_FLAG="-d memory_limit=1024M"

if [ -f "${PHP_INI_FILE}" ]; then
    # Try using directory path for -c (some PHP builds prefer this)
    PHP_INI_FLAG="-c ${SCRIPT_DIR}"
    echo -e "${GREEN}Found PHP configuration file: php.ini${NC}"
    echo "  Attempting to use custom PHP settings from: ${PHP_INI_FILE}"
    echo "  Note: Memory limit will also be set via command-line flag to ensure it's applied"
    echo "  You can edit this file to customize other PHP settings"
    echo ""
else
    echo -e "${YELLOW}Note: No php.ini file found. Using PHP defaults with command-line flags.${NC}"
    echo "  You can create a php.ini file in this directory to customize PHP settings"
    echo "  Expected location: ${PHP_INI_FILE}"
    echo ""
fi

# Create temporary directory for extracted OpenEMR
TMP_DIR=$(mktemp -d)
EXTRACT_DIR="${TMP_DIR}/openemr-extracted"
mkdir -p "${EXTRACT_DIR}"

# Cleanup function
cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "${TMP_DIR}" ]; then
        echo ""
        echo -e "${YELLOW}Cleaning up temporary directory...${NC}"
        rm -rf "${TMP_DIR}"
    fi
}

trap cleanup EXIT INT TERM

echo -e "${YELLOW}Extracting OpenEMR files from PHAR archive...${NC}"
echo "Note: Extraction is needed because web browsers request individual files"
echo "      (HTML, CSS, JavaScript, images) via HTTP URLs."
echo ""

# Extract the PHAR using the binary itself
# Create a script file for extraction
EXTRACT_SCRIPT="${TMP_DIR}/extract-phar.php"
cat > "${EXTRACT_SCRIPT}" << 'EXTRACTPHAR'
<?php
// Memory limit should be set via php.ini, but set it here too as a fallback
if (ini_get('memory_limit') < 512) {
    ini_set('memory_limit', '1024M');
}
ini_set('max_execution_time', '0');

$pharFile = $argv[1];
$extractDir = $argv[2];

try {
    $phar = new Phar($pharFile);
    $phar->extractTo($extractDir, null, true);
    echo "Extracted successfully\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
    exit(1);
}
EXTRACTPHAR

# Extract PHAR using PHP CLI binary
# The php.ini file will be automatically loaded from the script directory
# We also set explicit flags as a backup
if [ -f "${PHP_INI_FILE}" ]; then
    # Use php.ini directory - PHP will automatically load php.ini from there
    "${PHP_BIN}" \
        -c "${SCRIPT_DIR}" \
        -d memory_limit=1024M \
        -d max_execution_time=0 \
        "${EXTRACT_SCRIPT}" "${PHAR_FILE}" "${EXTRACT_DIR}" || {
        echo -e "${RED}ERROR: Failed to extract PHAR archive${NC}"
        echo "Used PHP CLI binary: $(basename "${PHP_BIN}")"
        echo "PHP config directory: ${SCRIPT_DIR}"
        echo ""
        echo "The PHAR file is large (~278MB) and requires more memory to extract."
        echo "Memory limit set: 1024M via php.ini and command-line flag"
        exit 1
    }
else
    # Fallback: use command-line flags only
    "${PHP_BIN}" \
        -d memory_limit=1024M \
        -d max_execution_time=0 \
        "${EXTRACT_SCRIPT}" "${PHAR_FILE}" "${EXTRACT_DIR}" || {
        echo -e "${RED}ERROR: Failed to extract PHAR archive${NC}"
        echo "Used PHP CLI binary: $(basename "${PHP_BIN}")"
        echo ""
        echo "The PHAR file is large (~278MB) and requires more memory to extract."
        echo "Memory limit set via command-line flag: 1024M"
        exit 1
    }
fi

if [ ! -d "${EXTRACT_DIR}" ] || [ -z "$(ls -A "${EXTRACT_DIR}" 2>/dev/null)" ]; then
    echo -e "${RED}ERROR: Failed to extract OpenEMR files${NC}"
    exit 1
fi

# OpenEMR's web root
WEB_ROOT="${EXTRACT_DIR}"

echo -e "${GREEN}✓ OpenEMR extracted successfully${NC}"
echo ""

# Check if port is available
if lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: Port ${PORT} is already in use${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get local IP address for network access
LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "localhost")

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Starting OpenEMR Web Server${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "Server information:"
echo "  Local URL:    http://localhost:${PORT}"
if [ "${LOCAL_IP}" != "localhost" ]; then
    echo "  Network URL:  http://${LOCAL_IP}:${PORT}"
fi
echo "  Web root:     ${WEB_ROOT}"
echo "  Using:        $(basename "${BINARY}") (self-contained)"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
echo ""

# Create router script for OpenEMR
ROUTER_SCRIPT="${TMP_DIR}/router.php"
cat > "${ROUTER_SCRIPT}" << 'ROUTER'
<?php
// Router for OpenEMR with PHP built-in server
$webRoot = getenv('OPENEMR_WEB_ROOT');
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$requestFile = $webRoot . $uri;

// Serve existing files directly (CSS, JS, images, etc.)
if ($uri !== '/' && file_exists($requestFile) && !is_dir($requestFile)) {
    return false;
}

// Route to OpenEMR entry point
$openemrEntryPoints = [
    $webRoot . '/interface/main/main.php',
    $webRoot . '/interface/main.php',
    $webRoot . '/main.php',
    $webRoot . '/index.php',
];

// Also check common alternative structures
if (is_dir($webRoot)) {
    $interfaceDir = $webRoot . '/interface';
    if (is_dir($interfaceDir)) {
        if (is_dir($interfaceDir . '/main')) {
            $openemrEntryPoints[] = $interfaceDir . '/main/main.php';
            $openemrEntryPoints[] = $interfaceDir . '/main/index.php';
        }
        $openemrEntryPoints[] = $interfaceDir . '/main.php';
        $openemrEntryPoints[] = $interfaceDir . '/index.php';
    }
}

foreach ($openemrEntryPoints as $entryPoint) {
    if (file_exists($entryPoint)) {
        $_SERVER['SCRIPT_NAME'] = $entryPoint;
        $_SERVER['PHP_SELF'] = $entryPoint;
        $_SERVER['DOCUMENT_ROOT'] = $webRoot;
        require $entryPoint;
        return;
    }
}

http_response_code(404);
echo "OpenEMR entry point not found. Expected: interface/main/main.php\n";
echo "Web root: " . $webRoot . "\n";
ROUTER

# Set the web root as an environment variable for the router
export OPENEMR_WEB_ROOT="${WEB_ROOT}"

# Change to web root for serving files
cd "${WEB_ROOT}"

echo -e "${GREEN}Starting web server...${NC}"
if [ -f "${PHP_INI_FILE}" ]; then
    echo -e "${BLUE}Using PHP configuration from: ${PHP_INI_FILE}${NC}"
fi
echo ""

# Start the server using the PHP CLI binary (supports php.ini)
# The -c flag tells PHP to load php.ini from the specified directory
# This works even when running from a different directory (WEB_ROOT)
if [ -n "${PHP_INI_FLAG}" ]; then
    "${PHP_BIN}" ${PHP_INI_FLAG} -S "0.0.0.0:${PORT}" -t "${WEB_ROOT}" "${ROUTER_SCRIPT}"
else
    "${PHP_BIN}" -S "0.0.0.0:${PORT}" -t "${WEB_ROOT}" "${ROUTER_SCRIPT}"
fi
