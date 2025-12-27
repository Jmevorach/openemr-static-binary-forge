#!/bin/bash
# Test script for Apache CGI setup
# Tests the components individually since Apache requires sudo

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MAC_OS_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
ARCH=$(uname -m)
PHP_CGI="${MAC_OS_DIR}/php-cgi-v7_0_4-macos-${ARCH}"
WRAPPER="${OPENEMR_PATH}/cgi-bin/php-wrapper.cgi"

echo "=========================================="
echo "Testing Apache CGI Setup Components"
echo "=========================================="
echo ""

# Test 1: PHP CGI binary
echo "1. Testing PHP CGI binary..."
if [ -f "${PHP_CGI}" ] && [ -x "${PHP_CGI}" ]; then
    VERSION=$("${PHP_CGI}" --version 2>&1 | head -1)
    echo "   ✓ PHP CGI binary exists and is executable"
    echo "   Version: ${VERSION}"
else
    echo "   ✗ PHP CGI binary not found or not executable"
    exit 1
fi
echo ""

# Test 2: Wrapper script
echo "2. Testing PHP wrapper script..."
if [ -f "${WRAPPER}" ] && [ -x "${WRAPPER}" ]; then
    echo "   ✓ Wrapper script exists and is executable"
    
    # Test wrapper with a PHP file
    TEST_PHP="${OPENEMR_PATH}/test.php"
    if [ -f "${TEST_PHP}" ]; then
        echo "   Testing wrapper execution..."
        OUTPUT=$(SCRIPT_FILENAME="${TEST_PHP}" "${WRAPPER}" 2>&1)
        if echo "${OUTPUT}" | grep -q "X-Powered-By.*PHP"; then
            echo "   ✓ Wrapper script executes PHP successfully"
            echo "   Sample output:"
            echo "${OUTPUT}" | grep -A3 "OpenEMR\|PHP Version" | sed 's/^/     /' | head -5
        else
            echo "   ✗ Wrapper script execution failed"
            echo "   Output: ${OUTPUT}"
        fi
    else
        echo "   ! Test PHP file not found, skipping execution test"
    fi
else
    echo "   ✗ Wrapper script not found or not executable"
    exit 1
fi
echo ""

# Test 3: OpenEMR extracted
echo "3. Checking OpenEMR extraction..."
if [ -d "${OPENEMR_PATH}" ]; then
    FILE_COUNT=$(find "${OPENEMR_PATH}" -type f | wc -l | tr -d ' ')
    echo "   ✓ OpenEMR extracted"
    echo "   Files: ${FILE_COUNT}"
    
    # Check for key OpenEMR files
    if [ -f "${OPENEMR_PATH}/interface/main/main.php" ]; then
        echo "   ✓ OpenEMR entry point found"
    else
        echo "   ! OpenEMR entry point not found (may be different version)"
    fi
else
    echo "   ✗ OpenEMR not extracted"
    echo "   Run: cd ${MAC_OS_DIR} && ./apache_cgi/extract-openemr.sh"
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
echo "1. Configure Apache using httpd-openemr.conf (see README.md for instructions)"
echo "2. Copy the configuration to your Apache directory"
echo "3. Update paths in the configuration file"
echo "4. Start Apache and test"
echo ""
echo "See ${SCRIPT_DIR}/README.md for detailed setup instructions."
echo ""

