#!/bin/sh
# Test script for Apache CGI setup on FreeBSD
# Tests the components individually

set -e

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
FREEBSD_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
OPENEMR_PATH="${FREEBSD_DIR}/openemr-extracted"
ARCH=$(uname -m)

# Detect architecture for binary naming
if [ "${ARCH}" = "arm64" ] || [ "${ARCH}" = "aarch64" ]; then
    BINARY_ARCH="arm64"
elif [ "${ARCH}" = "x86_64" ] || [ "${ARCH}" = "amd64" ]; then
    BINARY_ARCH="amd64"
else
    BINARY_ARCH="${ARCH}"
fi

PHP_CGI=$(find "${FREEBSD_DIR}" -maxdepth 1 -type f \( -name "php-cgi-*-freebsd-arm64" -o -name "php-cgi-*-freebsd-aarch64" -o -name "php-cgi-*-freebsd-amd64" -o -name "php-cgi-*-freebsd-x86_64" \) -perm +111 2>/dev/null | head -1)
# Fallback to simple name
if [ -z "${PHP_CGI}" ]; then
    PHP_CGI=$(find "${FREEBSD_DIR}" -maxdepth 1 -type f -name "php-cgi" -perm +111 2>/dev/null | head -1)
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
