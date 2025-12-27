#!/bin/bash
# Test script for Apache PHP-FPM setup
# Tests the components individually

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MAC_OS_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
ARCH=$(uname -m)
OPENEMR_PATH="${MAC_OS_DIR}/openemr-extracted"

echo "=========================================="
echo "Testing Apache PHP-FPM Setup Components"
echo "=========================================="
echo ""

# Test 1: PHP FPM binary
echo "1. Testing PHP FPM binary..."
PHP_FPM=$(find "${MAC_OS_DIR}" -maxdepth 1 -type f -name "php-fpm-*-macos-*" -perm +111 2>/dev/null | head -1)
if [ -n "${PHP_FPM}" ] && [ -x "${PHP_FPM}" ]; then
    VERSION=$("${PHP_FPM}" --version 2>&1 | head -1)
    echo "   ✓ PHP FPM binary exists and is executable"
    echo "   Version: ${VERSION}"
else
    echo "   ✗ PHP FPM binary not found or not executable"
    exit 1
fi
echo ""

# Test 2: PHP-FPM configuration
echo "2. Testing PHP-FPM configuration..."
FPM_CONF="${SCRIPT_DIR}/php-fpm.conf"
if [ -f "${FPM_CONF}" ]; then
    echo "   ✓ FPM configuration found: ${FPM_CONF}"
    # Test config syntax
    if "${PHP_FPM}" -t -y "${FPM_CONF}" 2>&1 | grep -q "test is successful"; then
        echo "   ✓ FPM configuration syntax is valid"
    else
        echo "   ✗ FPM configuration syntax check failed"
        "${PHP_FPM}" -t -y "${FPM_CONF}"
        exit 1
    fi
else
    echo "   ✗ FPM configuration not found"
    exit 1
fi
echo ""

# Test 3: PHP-FPM process
echo "3. Checking PHP-FPM process..."
if ps aux | grep -v grep | grep -q "php-fpm"; then
    echo "   ✓ PHP-FPM process is running"
    if lsof -i :9000 -sTCP:LISTEN >/dev/null 2>&1; then
        echo "   ✓ PHP-FPM is listening on port 9000"
    else
        echo "   ✗ PHP-FPM is NOT listening on port 9000"
    fi
else
    echo "   ! PHP-FPM process is not running"
    echo "   Run: ${SCRIPT_DIR}/run-fpm.sh"
fi
echo ""

# Test 4: OpenEMR extracted
echo "4. Checking OpenEMR extraction..."
if [ -d "${OPENEMR_PATH}" ]; then
    FILE_COUNT=$(find "${OPENEMR_PATH}" -type f | wc -l | tr -d ' ')
    echo "   ✓ OpenEMR extracted"
    echo "   Files: ${FILE_COUNT}"
else
    echo "   ✗ OpenEMR not extracted"
    echo "   Run: cd ${SCRIPT_DIR} && ./extract-openemr.sh"
    exit 1
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo "✓ PHP FPM binary: Ready"
echo "✓ FPM configuration: Ready"
echo "✓ OpenEMR extraction: Complete"
echo ""
echo "Next steps:"
echo "1. Start PHP-FPM using ${SCRIPT_DIR}/run-fpm.sh"
echo "2. Configure Apache using setup-apache-config.sh (requires sudo)"
echo "3. Restart Apache and visit http://localhost:8080/"
echo ""
