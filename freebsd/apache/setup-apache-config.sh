#!/bin/sh
# Script to update Apache configuration with correct paths for FreeBSD
# Run with: sudo ./setup-apache-config.sh

set -e

# Auto-detect script directory and project paths
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
FREEBSD_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
PROJECT_ROOT="$( cd "${FREEBSD_DIR}/.." && pwd )"
OPENEMR_PATH="${FREEBSD_DIR}/openemr-extracted"

# FreeBSD Apache configuration directory
APACHE_BASE_DIR="/usr/local/etc/apache24"
APACHE_EXTRA_DIR="${APACHE_BASE_DIR}/Includes"
HTTPD_CONF="${APACHE_BASE_DIR}/httpd.conf"

if [ ! -d "${APACHE_BASE_DIR}" ]; then
    echo "Error: Could not find Apache configuration directory at ${APACHE_BASE_DIR}"
    echo "Please install Apache first: pkg install apache24"
    exit 1
fi

mkdir -p "${APACHE_EXTRA_DIR}"
CONF_FILE="${APACHE_EXTRA_DIR}/openemr.conf"

echo "Apache CGI Setup for OpenEMR (FreeBSD)"
echo "=============================="
echo "Script directory: ${SCRIPT_DIR}"
echo "OpenEMR path: ${OPENEMR_PATH}"
echo "Apache config: ${CONF_FILE}"
echo ""

# Verify OpenEMR directory exists
if [ ! -d "${OPENEMR_PATH}" ]; then
    echo "Error: OpenEMR directory not found at ${OPENEMR_PATH}"
    echo "Please extract OpenEMR first using: cd ${FREEBSD_DIR} && ./apache/extract-openemr.sh"
    exit 1
fi

# Verify PHP CGI binary exists (wrapper script will auto-detect it)
PHP_CGI=$(find "${FREEBSD_DIR}" -maxdepth 1 -type f -name "php-cgi-*-freebsd-*" -perm +111 2>/dev/null | head -1)
if [ -z "${PHP_CGI}" ] || [ ! -f "${PHP_CGI}" ]; then
    echo "Warning: PHP CGI binary not found at ${FREEBSD_DIR}/php-cgi-*-freebsd-*"
    echo "The wrapper script will try to auto-detect it, but you may need to run:"
    echo "  cd ${FREEBSD_DIR} && ./build-freebsd.sh"
    echo ""
else
    echo "✓ Found PHP CGI binary: $(basename "${PHP_CGI}")"
fi

# Ensure cgi-bin directory exists
if [ ! -d "${OPENEMR_PATH}/cgi-bin" ]; then
    echo "Creating cgi-bin directory..."
    mkdir -p "${OPENEMR_PATH}/cgi-bin"
fi

# Copy and configure wrapper script
WRAPPER_SCRIPT="${OPENEMR_PATH}/cgi-bin/php-wrapper.cgi"
WRAPPER_TEMPLATE="${SCRIPT_DIR}/php-wrapper.sh"

echo "Setting up PHP wrapper script..."
cp "${WRAPPER_TEMPLATE}" "${WRAPPER_SCRIPT}"
chmod +x "${WRAPPER_SCRIPT}"
echo "✓ Wrapper script installed: ${WRAPPER_SCRIPT}"

# Create updated configuration file from template
# We'll use the existing httpd-openemr.conf as a base but replace placeholders
cat "${SCRIPT_DIR}/httpd-openemr.conf" > "${CONF_FILE}"

# Replace OPENEMR_PATH placeholder with actual path
# FreeBSD sed works with -i ''
sed -i '' "s|Define OPENEMR_PATH .*|Define OPENEMR_PATH ${OPENEMR_PATH}|g" "${CONF_FILE}"

echo "✓ Configuration file updated: ${CONF_FILE}"
echo "  Note: PHP CGI binary will be auto-detected by the wrapper script"

# Enable required Apache modules
echo "Enabling required Apache modules in ${HTTPD_CONF}..."

# Function to enable a module if it's commented out
enable_module() {
    local module_name="$1"
    local module_file="$2"
    
    # Check if already enabled
    if grep -q "^LoadModule ${module_name} ${module_file}" "${HTTPD_CONF}"; then
        echo "✓ ${module_name} already enabled"
        return 0
    fi
    
    # Check if commented out and uncomment it
    if grep -q "^#LoadModule ${module_name} ${module_file}" "${HTTPD_CONF}"; then
        sed -i '' "s|^#LoadModule ${module_name} ${module_file}|LoadModule ${module_name} ${module_file}|g" "${HTTPD_CONF}"
        echo "✓ Enabled ${module_name}"
        return 0
    fi
    
    # If not found, add it
    echo "LoadModule ${module_name} ${module_file}" >> "${HTTPD_CONF}"
    echo "✓ Added ${module_name}"
}

# FreeBSD module paths are relative to /usr/local
enable_module "rewrite_module" "libexec/apache24/mod_rewrite.so"
enable_module "actions_module" "libexec/apache24/mod_actions.so"
enable_module "deflate_module" "libexec/apache24/mod_deflate.so"
enable_module "cgi_module" "libexec/apache24/mod_cgi.so"
enable_module "headers_module" "libexec/apache24/mod_headers.so"
enable_module "expires_module" "libexec/apache24/mod_expires.so"

echo ""

# Test configuration
echo "Testing Apache configuration..."
if apachectl configtest; then
    echo ""
    echo "✓ Configuration is valid!"
    echo ""
    echo "Next steps:"
    echo "  1. Enable Apache at boot: sysrc apache24_enable=YES"
    echo "  2. Start/Restart Apache: service apache24 restart"
    echo "  3. Test: curl http://localhost/test.php"
else
    echo "✗ Configuration test failed. Please check the errors above."
    exit 1
fi
