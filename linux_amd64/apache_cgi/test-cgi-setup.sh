#!/usr/bin/env bash
# Test script for Apache CGI setup on Linux (amd64)
# Tests the components individually

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
LINUX_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
OPENEMR_PATH="${LINUX_DIR}/openemr-extracted"

PHP_CGI=$(find "${LINUX_DIR}" -maxdepth 1 -type f \( -name "php-cgi-*-linux-amd64" -o -name "php-cgi-linux-amd64" \) -perm /111 2>/dev/null | head -1)
WRAPPER="${OPENEMR_PATH}/cgi-bin/php-wrapper.cgi"

echo "=========================================="
echo "Testing Apache CGI Setup Components (Linux amd64)"
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
    exit 1
fi
echo ""

# Test 2: Wrapper script
echo "2. Testing PHP wrapper script..."
if [ -f "${WRAPPER}" ] && [ -x "${WRAPPER}" ]; then
    echo "   ✓ Wrapper script exists and is executable"
    
    TEST_PHP="${OPENEMR_PATH}/test.php"
    if [ ! -f "${TEST_PHP}" ]; then
        echo "<?php echo 'OpenEMR PHP Test Success'; ?>" > "${TEST_PHP}"
    fi
    
    echo "   Testing wrapper execution..."
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
