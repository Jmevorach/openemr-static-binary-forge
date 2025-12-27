#!/usr/bin/env bash
# Script to update Apache configuration with correct paths for Linux (arm64)
# Run with: sudo ./setup-apache-config.sh

set -euo pipefail

# Auto-detect script directory and project paths
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
LINUX_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
OPENEMR_PATH="${LINUX_DIR}/openemr-extracted"

# Linux Apache configuration directory (Debian/Ubuntu style)
APACHE_BASE_DIR="/etc/apache2"
SITES_AVAILABLE="${APACHE_BASE_DIR}/sites-available"
CONF_FILE="${SITES_AVAILABLE}/openemr.conf"

if [ ! -d "${APACHE_BASE_DIR}" ]; then
    echo "Error: Could not find Apache configuration directory at ${APACHE_BASE_DIR}"
    echo "Please install Apache first: sudo apt update && sudo apt install apache2"
    exit 1
fi

echo "Apache CGI Setup for OpenEMR (Linux arm64)"
echo "=============================="
echo "Script directory: ${SCRIPT_DIR}"
echo "OpenEMR path: ${OPENEMR_PATH}"
echo "Apache config: ${CONF_FILE}"
echo ""

# Verify OpenEMR directory exists
if [ ! -d "${OPENEMR_PATH}" ]; then
    echo "Error: OpenEMR directory not found at ${OPENEMR_PATH}"
    echo "Please extract OpenEMR first using: cd ${SCRIPT_DIR} && ./extract-openemr.sh"
    exit 1
fi

# Verify PHP CGI binary exists
PHP_CGI=$(find "${LINUX_DIR}" -maxdepth 1 -type f \( -name "php-cgi-*-linux-arm64" -o -name "php-cgi-linux-arm64" \) -perm /111 2>/dev/null | head -1)
if [ -z "${PHP_CGI}" ]; then
    echo "Warning: PHP CGI binary not found at ${LINUX_DIR}/php-cgi-*-linux-arm64"
    echo "The wrapper script will try to auto-detect it, but you may need to run:"
    echo "  cd ${LINUX_DIR} && ./build-linux.sh"
    echo ""
else
    echo "✓ Found PHP CGI binary: $(basename "${PHP_CGI}")"
fi

# Ensure cgi-bin directory exists
mkdir -p "${OPENEMR_PATH}/cgi-bin"

# Copy and configure wrapper script
WRAPPER_SCRIPT="${OPENEMR_PATH}/cgi-bin/php-wrapper.cgi"
WRAPPER_TEMPLATE="${SCRIPT_DIR}/php-wrapper.sh"

echo "Setting up PHP wrapper script..."
cp "${WRAPPER_TEMPLATE}" "${WRAPPER_SCRIPT}"
chmod +x "${WRAPPER_SCRIPT}"
echo "✓ Wrapper script installed: ${WRAPPER_SCRIPT}"

# Create updated configuration file from template
cat "${SCRIPT_DIR}/httpd-openemr.conf" > "${CONF_FILE}"

# Replace OPENEMR_PATH placeholder with actual path
sed -i "s|Define OPENEMR_PATH .*|Define OPENEMR_PATH ${OPENEMR_PATH}|g" "${CONF_FILE}"

echo "✓ Configuration file created: ${CONF_FILE}"

# Set permissions for OpenEMR
echo "Setting file permissions for OpenEMR..."
# Ensure the web server can write to the necessary directories
# First, create directories/files if they don't exist
mkdir -p "${OPENEMR_PATH}/sites/default/documents"
mkdir -p "${OPENEMR_PATH}/sites/default/edi"
mkdir -p "${OPENEMR_PATH}/sites/default/era"
mkdir -p "${OPENEMR_PATH}/sites/default/letter_templates"
mkdir -p "${OPENEMR_PATH}/gdata"
touch "${OPENEMR_PATH}/sites/default/sqlconf.php"

# Set ownership to www-data
chown -R www-data:www-data "${OPENEMR_PATH}"

# Set specific permissions as requested by the OpenEMR installer
chmod 666 "${OPENEMR_PATH}/sites/default/sqlconf.php"
chmod 777 "${OPENEMR_PATH}/sites/default/documents"
chmod 777 "${OPENEMR_PATH}/sites/default/edi"
chmod 777 "${OPENEMR_PATH}/sites/default/era"
chmod 777 "${OPENEMR_PATH}/sites/default/letter_templates"
chmod 777 "${OPENEMR_PATH}/gdata"
echo "✓ Permissions updated"

# Enable required Apache modules
echo "Enabling required Apache modules..."
a2enmod rewrite actions cgi headers expires deflate

# Enable the site
echo "Enabling OpenEMR site..."
a2ensite openemr

# Test configuration
echo "Testing Apache configuration..."
if apache2ctl configtest; then
    echo ""
    echo "✓ Configuration is valid!"
    echo ""
    echo "Next steps:"
    echo "  1. Restart Apache: sudo systemctl restart apache2"
    echo "  2. Test: curl http://localhost/test.php"
else
    echo "✗ Configuration test failed. Please check the errors above."
    exit 1
fi
