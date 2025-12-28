#!/usr/bin/env bash
# Extract OpenEMR PHAR Archive on FreeBSD

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FREEBSD_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Smart detection of DIST_DIR
if [ -d "${FREEBSD_DIR}/dist" ]; then
    DIST_DIR="${FREEBSD_DIR}/dist"
elif [ -d "${FREEBSD_DIR}/bin" ] && [ -f "${FREEBSD_DIR}/openemr.phar" ]; then
    # We are likely inside the VM or in a flat distribution directory
    DIST_DIR="${FREEBSD_DIR}"
else
    DIST_DIR="${FREEBSD_DIR}/dist"
fi

# Default output directory
OUTPUT_DIR="${1:-${FREEBSD_DIR}/openemr-extracted}"

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Extracting OpenEMR PHAR Archive (FreeBSD)${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""

# Find the PHP CLI binary
PHP_CLI_BINARY=""
# 1. Try common standalone names (from dist/ folder)
PHP_CLI_BINARY=$(find "${DIST_DIR}" -maxdepth 1 -type f -name "php-cli-*-freebsd-*" -perm +111 2>/dev/null | head -1)

# 2. Try standard bin/php path (from tarball extraction)
if [ -z "${PHP_CLI_BINARY}" ] || [ ! -f "${PHP_CLI_BINARY}" ]; then
    if [ -f "${DIST_DIR}/bin/php" ]; then
        PHP_CLI_BINARY="${DIST_DIR}/bin/php"
    fi
fi

if [ -z "${PHP_CLI_BINARY}" ] || [ ! -f "${PHP_CLI_BINARY}" ]; then
    echo -e "${RED}ERROR: PHP CLI binary not found${NC}"
    echo "Checked: ${DIST_DIR}/php-cli-*-freebsd-* and ${DIST_DIR}/bin/php"
    echo ""
    echo "Please build the binary first using: cd ${FREEBSD_DIR} && ./build-freebsd.sh"
    exit 1
fi

# Find the PHAR file
PHAR_FILE=""
# 1. Try common standalone names
PHAR_FILE=$(find "${DIST_DIR}" -maxdepth 1 -type f -name "openemr-*.phar" 2>/dev/null | head -1)

# 2. Try standard openemr.phar name
if [ -z "${PHAR_FILE}" ] || [ ! -f "${PHAR_FILE}" ]; then
    if [ -f "${DIST_DIR}/openemr.phar" ]; then
        PHAR_FILE="${DIST_DIR}/openemr.phar"
    fi
fi

if [ -z "${PHAR_FILE}" ] || [ ! -f "${PHAR_FILE}" ]; then
    echo -e "${RED}ERROR: OpenEMR PHAR file not found${NC}"
    echo "Checked: ${DIST_DIR}/openemr-*.phar and ${DIST_DIR}/openemr.phar"
    echo ""
    echo "Please build the binary first using: cd ${FREEBSD_DIR} && ./build-freebsd.sh"
    exit 1
fi

# Remove existing directory if it exists
if [ -d "${OUTPUT_DIR}" ]; then
    echo -e "${YELLOW}Removing existing directory: ${OUTPUT_DIR}${NC}"
    rm -rf "${OUTPUT_DIR}"
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"

echo -e "${YELLOW}Extracting OpenEMR PHAR archive...${NC}"
echo "Source: ${PHAR_FILE}"
echo "Destination: ${OUTPUT_DIR}"
echo ""

# Set library path for bundled libraries if they exist
export LD_LIBRARY_PATH="${DIST_DIR}/lib:${LD_LIBRARY_PATH:-}"

# Extract using PHP CLI binary
"${PHP_CLI_BINARY}" -r "
    ini_set('memory_limit', '1024M');
    ini_set('max_execution_time', '0');
    \$pharFile = '${PHAR_FILE}';
    \$extractDir = '${OUTPUT_DIR}';
    
    try {
        \$phar = new Phar(\$pharFile);
        echo 'Extracting ' . \$phar->count() . ' files...' . PHP_EOL;
        \$phar->extractTo(\$extractDir, null, true);
        echo 'Extracted successfully!' . PHP_EOL;
    } catch (Exception \$e) {
        echo 'Error: ' . \$e->getMessage() . PHP_EOL;
        exit(1);
    }
" || {
    echo -e "${RED}ERROR: Failed to extract OpenEMR PHAR${NC}"
    exit 1
}

echo ""
echo -e "${GREEN}✓ OpenEMR extracted successfully${NC}"
echo "  Directory: ${OUTPUT_DIR}"
echo ""
