#!/usr/bin/env bash
# ==============================================================================
# Extract OpenEMR PHAR Archive
# ==============================================================================
# This script extracts the OpenEMR PHAR archive using the static PHP CLI binary.
#
# Usage:
#   ./extract-openemr.sh [output_directory]
#
# Example:
#   ./extract-openemr.sh
#   ./extract-openemr.sh /path/to/openemr-extracted
#
# Default output directory: ../openemr-extracted (relative to this script)
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Default output directory
OUTPUT_DIR="${1:-${PARENT_DIR}/openemr-extracted}"

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Extracting OpenEMR PHAR Archive${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""

# Find the PHP CLI binary
PHP_CLI_PATTERN="php-cli-*-macos-*"
PHP_CLI_BINARY=$(find "${PARENT_DIR}" -maxdepth 1 -type f -name "${PHP_CLI_PATTERN}" -perm +111 2>/dev/null | head -1)

if [ -z "${PHP_CLI_BINARY}" ] || [ ! -f "${PHP_CLI_BINARY}" ]; then
    echo -e "${RED}ERROR: PHP CLI binary not found${NC}"
    echo "Expected: ${PARENT_DIR}/${PHP_CLI_PATTERN}"
    echo ""
    echo "Please build the binary first using: cd ${PARENT_DIR} && ./build-macos.sh"
    exit 1
fi

echo -e "${GREEN}Found PHP CLI binary: $(basename "${PHP_CLI_BINARY}")${NC}"
echo ""

# Find the PHAR file
PHAR_PATTERN="openemr-*.phar"
PHAR_FILE=$(find "${PARENT_DIR}" -maxdepth 1 -type f -name "${PHAR_PATTERN}" 2>/dev/null | head -1)

if [ -z "${PHAR_FILE}" ] || [ ! -f "${PHAR_FILE}" ]; then
    echo -e "${RED}ERROR: OpenEMR PHAR file not found${NC}"
    echo "Expected: ${PARENT_DIR}/${PHAR_PATTERN}"
    echo ""
    echo "Please build the binary first using: cd ${PARENT_DIR} && ./build-macos.sh"
    exit 1
fi

echo -e "${GREEN}Found PHAR file: $(basename "${PHAR_FILE}")${NC}"
echo ""

# Check if output directory already exists and has content
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

if [ ! -d "${OUTPUT_DIR}" ] || [ -z "$(ls -A "${OUTPUT_DIR}" 2>/dev/null)" ]; then
    echo -e "${RED}ERROR: Extraction failed or directory is empty${NC}"
    exit 1
fi

FILE_COUNT=$(find "${OUTPUT_DIR}" -type f | wc -l | tr -d ' ')
DIR_SIZE=$(du -sh "${OUTPUT_DIR}" | cut -f1)

echo ""
echo -e "${GREEN}✓ OpenEMR extracted successfully${NC}"
echo "  Directory: ${OUTPUT_DIR}"
echo "  Files: ${FILE_COUNT}"
echo "  Size: ${DIR_SIZE}"
echo ""
echo "Next steps:"
echo "  1. Update OPENEMR_PATH in httpd-openemr.conf to: ${OUTPUT_DIR}"
echo "  2. Start PHP-FPM using run-fpm.sh"
echo "  3. Copy httpd-openemr.conf to Apache extra directory"
echo "  4. Include it in Apache main configuration"
echo "  5. Restart Apache"
echo ""
