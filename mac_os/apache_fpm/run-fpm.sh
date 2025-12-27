#!/usr/bin/env bash
# Script to run PHP-FPM with the static binary on macOS

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MAC_OS_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Find the PHP FPM binary
PHP_FPM_PATTERN="php-fpm-*-macos-*"
PHP_FPM_BINARY=$(find "${MAC_OS_DIR}" -maxdepth 1 -type f -name "${PHP_FPM_PATTERN}" -perm +111 2>/dev/null | head -1)

if [ -z "${PHP_FPM_BINARY}" ] || [ ! -f "${PHP_FPM_BINARY}" ]; then
    echo -e "${RED}ERROR: PHP FPM binary not found${NC}"
    echo "Expected: ${MAC_OS_DIR}/${PHP_FPM_PATTERN}"
    echo ""
    echo "Please build the binary first using: cd ${MAC_OS_DIR}/.. && ./build-macos.sh"
    exit 1
fi

# Check for php.ini in mac_os directory
PHP_INI="${MAC_OS_DIR}/php.ini"
PHP_INI_OPT=""
if [ -f "${PHP_INI}" ]; then
    PHP_INI_OPT="-c ${PHP_INI}"
    echo -e "${GREEN}Using php.ini: ${PHP_INI}${NC}"
fi

FPM_CONF="${SCRIPT_DIR}/php-fpm.conf"
if [ ! -f "${FPM_CONF}" ]; then
    echo -e "${RED}ERROR: PHP-FPM config not found: ${FPM_CONF}${NC}"
    exit 1
fi

echo -e "${GREEN}Starting PHP-FPM...${NC}"
echo "Binary: ${PHP_FPM_BINARY}"
echo "Config: ${FPM_CONF}"

# Run PHP-FPM
# -y: path to fpm conf
# -c: path to php.ini (if provided)
"${PHP_FPM_BINARY}" -y "${FPM_CONF}" ${PHP_INI_OPT}

echo -e "${GREEN}✓ PHP-FPM started successfully (background)${NC}"
echo "To stop PHP-FPM, run: kill \$(cat /tmp/php-fpm.pid)"
