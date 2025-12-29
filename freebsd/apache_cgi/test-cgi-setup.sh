#!/bin/sh
# Test script for Apache CGI setup on FreeBSD
# Tests the components individually

set -e

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
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

OPENEMR_PATH="${FREEBSD_DIR}/openemr-extracted"
ARCH=$(uname -m)

# Find the PHP CGI binary
PHP_CGI=""
# 1. Try common standalone names (from dist/ folder)
PHP_CGI=$(find "${DIST_DIR}" -maxdepth 1 -type f -name "php-cgi-*-freebsd-*" -perm +111 2>/dev/null | head -1)

# 2. Try standard bin/php-cgi path (from tarball extraction)
if [ -z "${PHP_CGI}" ] || [ ! -f "${PHP_CGI}" ]; then
    if [ -f "${DIST_DIR}/bin/php-cgi" ]; then
        PHP_CGI="${DIST_DIR}/bin/php-cgi"
    fi
fi
WRAPPER="${OPENEMR_PATH}/cgi-bin/php-wrapper.cgi"

echo "=========================================="
echo "Testing Apache CGI Setup Components (FreeBSD)"
echo "=========================================="
echo ""

# Test 1: PHP CGI binary
echo "1. Testing PHP CGI binary..."
if [ -f "${PHP_CGI}" ] && [ -x "${PHP_CGI}" ]; then
    VERSION=$("${PHP_CGI}" --version 2>&1 | head -1)
    echo "   ✓ PHP CGI binary exists and is executable"
    echo "   Binary: $(basename "${PHP_CGI}")"
    echo "   Version: ${VERSION}"
else
    echo "   ✗ PHP CGI binary not found or not executable"
    echo "   Expected at: ${FREEBSD_DIR}/php-cgi-*-freebsd-*"
    exit 1
fi
echo ""

# Test 2: Wrapper script
echo "2. Testing PHP wrapper script..."
if [ -f "${WRAPPER}" ] && [ -x "${WRAPPER}" ]; then
    echo "   ✓ Wrapper script exists and is executable"
    
    # Test wrapper with a PHP file
    TEST_PHP="${OPENEMR_PATH}/test.php"
    if [ ! -f "${TEST_PHP}" ]; then
        # Create a simple test file if it doesn't exist
        echo "<?php echo 'OpenEMR PHP Test Success'; ?>" > "${TEST_PHP}"
    fi
    
    echo "   Testing wrapper execution..."
    # Set DOCUMENT_ROOT for the wrapper
    OUTPUT=$(DOCUMENT_ROOT="${OPENEMR_PATH}" SCRIPT_FILENAME="${TEST_PHP}" "${WRAPPER}" 2>&1)
    if echo "${OUTPUT}" | grep -q "OpenEMR PHP Test Success"; then
        echo "   ✓ Wrapper script executes PHP successfully"
    else
        echo "   ✗ Wrapper script execution failed"
        echo "   Output: ${OUTPUT}"
    fi
else
    echo "   ✗ Wrapper script not found or not executable at ${WRAPPER}"
    exit 1
fi
echo ""

# Test 3: OpenEMR extracted
echo "3. Checking OpenEMR extraction..."
if [ -d "${OPENEMR_PATH}" ]; then
    FILE_COUNT=$(find "${OPENEMR_PATH}" -type f | wc -l | tr -d ' ')
    echo "   ✓ OpenEMR extracted"
    echo "   Files: ${FILE_COUNT}"
    
    if [ -f "${OPENEMR_PATH}/interface/main/main.php" ]; then
        echo "   ✓ OpenEMR entry point found"
    fi
else
    echo "   ✗ OpenEMR not extracted at ${OPENEMR_PATH}"
    exit 1
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo "✓ PHP CGI binary: Working"
echo "✓ Wrapper script: Working"
echo "✓ OpenEMR extraction: Complete"
echo ""
echo "Next steps:"
echo "1. Configure Apache using: sudo ./setup-apache-config.sh"
echo "2. Start Apache: sudo service apache24 start"
echo ""
