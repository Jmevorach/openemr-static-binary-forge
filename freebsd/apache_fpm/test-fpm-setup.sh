#!/usr/bin/env bash
# Test script for Apache PHP-FPM setup on FreeBSD
# Tests the components individually

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FREEBSD_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
OPENEMR_PATH="${FREEBSD_DIR}/openemr-extracted"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Testing Apache PHP-FPM Setup (FreeBSD)${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Smart detection of DIST_DIR
if [ -d "${FREEBSD_DIR}/dist" ]; then
    DIST_DIR="${FREEBSD_DIR}/dist"
elif [ -d "${FREEBSD_DIR}/bin" ] && [ -f "${FREEBSD_DIR}/openemr.phar" ]; then
    DIST_DIR="${FREEBSD_DIR}"
else
    DIST_DIR="${FREEBSD_DIR}/dist"
fi

# Set library path for bundled libraries if they exist
export LD_LIBRARY_PATH="${DIST_DIR}/lib:/usr/local/lib:${LD_LIBRARY_PATH:-}"

# Detect architecture for binary naming
ARCH=$(uname -m)
if [ "${ARCH}" = "arm64" ] || [ "${ARCH}" = "aarch64" ]; then
    BINARY_ARCH="arm64"
elif [ "${ARCH}" = "x86_64" ] || [ "${ARCH}" = "amd64" ]; then
    BINARY_ARCH="amd64"
else
    BINARY_ARCH="${ARCH}"
fi

# Test 1: PHP FPM binary
echo "1. Testing PHP FPM binary..."
PHP_FPM=$(find "${DIST_DIR}" -maxdepth 1 -type f \( -name "php-fpm-*-freebsd-arm64" -o -name "php-fpm-*-freebsd-aarch64" -o -name "php-fpm-*-freebsd-amd64" -o -name "php-fpm-*-freebsd-x86_64" \) -perm +111 2>/dev/null | head -1)

if [ -z "${PHP_FPM}" ] || [ ! -f "${PHP_FPM}" ]; then
    if [ -f "${DIST_DIR}/bin/php-fpm" ]; then
        PHP_FPM="${DIST_DIR}/bin/php-fpm"
    fi
fi

if [ -n "${PHP_FPM}" ] && [ -x "${PHP_FPM}" ]; then
    VERSION=$("${PHP_FPM}" --version 2>&1 | head -1)
    echo -e "   ${GREEN}✓${NC} PHP FPM binary exists: ${PHP_FPM}"
    echo "   Version: ${VERSION}"
else
    echo -e "   ${RED}✗${NC} PHP FPM binary not found or not executable"
    echo "   Checked: ${DIST_DIR}/php-fpm-*-freebsd-* and ${DIST_DIR}/bin/php-fpm"
    exit 1
fi
echo ""

# Test 2: PHP-FPM configuration
echo "2. Testing PHP-FPM configuration..."
FPM_CONF="${SCRIPT_DIR}/php-fpm.conf"
if [ -f "${FPM_CONF}" ]; then
    echo -e "   ${GREEN}✓${NC} FPM configuration found: ${FPM_CONF}"
    # Test config syntax
    if "${PHP_FPM}" -t -y "${FPM_CONF}" 2>&1 | grep -q "test is successful"; then
        echo -e "   ${GREEN}✓${NC} FPM configuration syntax is valid"
    else
        echo -e "   ${RED}✗${NC} FPM configuration syntax check failed"
        "${PHP_FPM}" -t -y "${FPM_CONF}"
        exit 1
    fi
else
    echo -e "   ${RED}✗${NC} FPM configuration not found"
    exit 1
fi
echo ""

# Test 3: PHP-FPM process
echo "3. Checking PHP-FPM process..."
if ps aux | grep -v grep | grep -q "php-fpm"; then
    echo -e "   ${GREEN}✓${NC} PHP-FPM process is running"
    if sockstat -l -p 9000 | grep -q ":9000"; then
        echo -e "   ${GREEN}✓${NC} PHP-FPM is listening on port 9000"
    else
        echo -e "   ${YELLOW}!${NC} PHP-FPM is NOT listening on port 9000"
    fi
else
    echo -e "   ${YELLOW}!${NC} PHP-FPM process is not running"
    echo "   Run: ${SCRIPT_DIR}/run-fpm.sh"
    # Don't exit here, keep checking other components
fi
echo ""

# Test 4: OpenEMR extracted
echo "4. Checking OpenEMR extraction..."
if [ -d "${OPENEMR_PATH}" ]; then
    FILE_COUNT=$(find "${OPENEMR_PATH}" -type f | wc -l | tr -d ' ')
    echo -e "   ${GREEN}✓${NC} OpenEMR extracted"
    echo "   Files: ${FILE_COUNT}"
else
    echo -e "   ${YELLOW}!${NC} OpenEMR not extracted at ${OPENEMR_PATH}"
    echo "   Run: cd ${SCRIPT_DIR} && ./extract-openemr.sh"
fi
echo ""

# Test 5: Apache configuration
echo "5. Checking Apache configuration..."
if [ -f "/usr/local/etc/apache24/Includes/httpd-openemr-fpm.conf" ]; then
    echo -e "   ${GREEN}✓${NC} Apache FPM configuration found in Includes/"
else
    echo -e "   ${YELLOW}!${NC} Apache FPM configuration not found"
    echo "   Run: sudo ${SCRIPT_DIR}/setup-apache-config.sh"
fi

if service apache24 status >/dev/null 2>&1; then
    echo -e "   ${GREEN}✓${NC} Apache service is running"
else
    echo -e "   ${YELLOW}!${NC} Apache service is not running"
fi
echo ""

echo -e "${GREEN}==========================================${NC}"
echo "Summary"
echo -e "${GREEN}==========================================${NC}"
echo "Next steps:"
echo "1. If any components are missing, run the respective setup scripts."
echo "2. Visit: http://localhost/ (if Apache is running)"
echo ""

