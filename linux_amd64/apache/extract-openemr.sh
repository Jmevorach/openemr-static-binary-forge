#!/usr/bin/env bash
# ==============================================================================
# Extract OpenEMR PHAR Archive for Linux (amd64)
# ==============================================================================
# This script extracts the OpenEMR PHAR archive using the static PHP CLI binary.

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
echo -e "${GREEN}Extracting OpenEMR PHAR Archive (Linux amd64)${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""

# Find the PHP CLI binary
PHP_CLI_PATTERN="php-cli-*-linux-amd64"
PHP_CLI_BINARY=$(find "${PARENT_DIR}" -maxdepth 1 -type f \( -name "${PHP_CLI_PATTERN}" -o -name "php-cli-linux-amd64" \) -perm /111 2>/dev/null | head -1)

if [ -z "${PHP_CLI_BINARY}" ] || [ ! -f "${PHP_CLI_BINARY}" ]; then
    echo -e "${RED}ERROR: PHP CLI binary not found${NC}"
    echo "Expected: ${PARENT_DIR}/${PHP_CLI_PATTERN}"
    echo ""
    echo "Please build the binary first using: cd ${PARENT_DIR} && ./build-linux.sh"
    exit 1
fi

echo -e "${GREEN}Found PHP CLI binary: $(basename "${PHP_CLI_BINARY}")${NC}"

# Find the PHAR file
PHAR_FILE=$(find "${PARENT_DIR}" -maxdepth 1 -type f \( -name "openemr-*.phar" -o -name "openemr.phar" \) 2>/dev/null | head -1)

if [ -z "${PHAR_FILE}" ] || [ ! -f "${PHAR_FILE}" ]; then
    echo -e "${RED}ERROR: OpenEMR PHAR file not found${NC}"
    exit 1
fi

echo -e "${GREEN}Found PHAR file: $(basename "${PHAR_FILE}")${NC}"
echo ""

# Check if output directory already exists
if [ -d "${OUTPUT_DIR}" ] && [ -n "$(ls -A "${OUTPUT_DIR}" 2>/dev/null)" ]; then
    if [[ "${1:-}" == "-y" ]] || [[ "${2:-}" == "-y" ]] || [[ "${AUTO_CONFIRM:-}" == "true" ]]; then
        echo -e "${YELLOW}Auto-confirming overwrite of existing directory: ${OUTPUT_DIR}${NC}"
        rm -rf "${OUTPUT_DIR}"
    else
        echo -e "${YELLOW}Warning: Output directory already exists and is not empty: ${OUTPUT_DIR}${NC}"
        echo -n "Continue and overwrite? (y/N): "
        read -r reply
        if [[ ! $reply =~ ^[Yy]$ ]]; then
            exit 1
        fi
        rm -rf "${OUTPUT_DIR}"
    fi
fi

mkdir -p "${OUTPUT_DIR}"

echo -e "${YELLOW}Extracting OpenEMR PHAR archive...${NC}"
"${PHP_CLI_BINARY}" -r "
    ini_set('memory_limit', '1024M');
    \$phar = new Phar('${PHAR_FILE}');
    \$phar->extractTo('${OUTPUT_DIR}', null, true);
"

echo -e "${GREEN}✓ OpenEMR extracted successfully to ${OUTPUT_DIR}${NC}"
