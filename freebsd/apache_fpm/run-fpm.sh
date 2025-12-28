#!/usr/bin/env bash
# Script to run PHP-FPM with the static binary on FreeBSD

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

# Find the PHP FPM binary
PHP_FPM_BINARY=""
# 1. Try common standalone names
PHP_FPM_BINARY=$(find "${DIST_DIR}" -maxdepth 1 -type f -name "php-fpm-*-freebsd-*" -perm +111 2>/dev/null | head -1)

# 2. Try standard bin/php-fpm path
if [ -z "${PHP_FPM_BINARY}" ] || [ ! -f "${PHP_FPM_BINARY}" ]; then
    if [ -f "${DIST_DIR}/bin/php-fpm" ]; then
        PHP_FPM_BINARY="${DIST_DIR}/bin/php-fpm"
    fi
fi

if [ -z "${PHP_FPM_BINARY}" ] || [ ! -f "${PHP_FPM_BINARY}" ]; then
    echo -e "${RED}ERROR: PHP FPM binary not found${NC}"
    echo "Checked: ${DIST_DIR}/php-fpm-*-freebsd-* and ${DIST_DIR}/bin/php-fpm"
    echo ""
    echo "Please build the binary first using: cd ${FREEBSD_DIR} && ./build-freebsd.sh"
    exit 1
fi

# Check for php.ini in freebsd directory
PHP_INI="${FREEBSD_DIR}/php.ini"
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

# Set library path for bundled libraries if they exist
export LD_LIBRARY_PATH="${DIST_DIR}/lib:/usr/local/lib:${LD_LIBRARY_PATH:-}"

# Run PHP-FPM
# -y: path to fpm conf
# -c: path to php.ini (if provided)
# -R: allow running as root (needed in some FreeBSD environments)
"${PHP_FPM_BINARY}" -y "${FPM_CONF}" ${PHP_INI_OPT} -R

echo -e "${GREEN}✓ PHP-FPM started successfully (background)${NC}"
echo "To stop PHP-FPM, run: kill \$(cat /tmp/php-fpm.pid)"
