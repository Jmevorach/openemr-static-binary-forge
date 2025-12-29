#!/usr/bin/env bash
# Script to update Apache configuration with correct paths for Linux (amd64) - FPM
# Run with: sudo ./setup-apache-config.sh

set -euo pipefail

# Auto-detect script directory and project paths
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
LINUX_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
OPENEMR_PATH="${LINUX_DIR}/openemr-extracted"

# Linux Apache configuration directory (Debian/Ubuntu style)
APACHE_BASE_DIR="/etc/apache2"
SITES_AVAILABLE="${APACHE_BASE_DIR}/sites-available"
CONF_FILE="${SITES_AVAILABLE}/openemr-fpm.conf"

if [ ! -d "${APACHE_BASE_DIR}" ]; then
    echo "Error: Could not find Apache configuration directory at ${APACHE_BASE_DIR}"
    echo "Please install Apache first: sudo apt update && sudo apt install apache2"
    exit 1
fi

echo "Apache PHP-FPM Setup for OpenEMR (Linux amd64)"
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

# Create updated configuration file from template
cat > "${CONF_FILE}" << APACHE_CONFIG_EOF
# Apache Virtual Host Configuration for OpenEMR (PHP-FPM)
# 
# This configuration uses PHP-FPM via mod_proxy_fcgi to execute PHP files.

# Paths - automatically configured
Define OPENEMR_PATH ${OPENEMR_PATH}

<VirtualHost *:80>
    ServerName localhost
    DocumentRoot "\${OPENEMR_PATH}"
    
    # Enable mod_rewrite for redirects
    RewriteEngine On
    
    # Redirect root to index.php if no file is specified
    RewriteRule ^$ /index.php [L]
    
    # Proxy PHP requests to PHP-FPM
    <FilesMatch \.php$>
        SetHandler "proxy:fcgi://127.0.0.1:9000"
    </FilesMatch>

    # ---------------------------------------------------------
    # Optimization for Heavy Load
    # ---------------------------------------------------------
    
    # Enable compression to reduce bandwidth usage
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript application/json
    </IfModule>

    # Connection optimizations
    KeepAlive On
    MaxKeepAliveRequests 100
    KeepAliveTimeout 5

    # Directory configuration
    <Directory "\${OPENEMR_PATH}">
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
        
        # Security: Prevent access to sensitive files
        <FilesMatch "\.(git|sql|ini|log|json|lock|md)\$">
            Require all denied
        </FilesMatch>
        
        # Deny access to hidden files
        <FilesMatch "^\.">
            Require all denied
        </FilesMatch>
    </Directory>
    
    # Static file handling
    <FilesMatch "\.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)\$">
        ExpiresActive On
        ExpiresDefault "access plus 1 year"
    </FilesMatch>
    
    # Security headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    
    # Logging
    ErrorLog \${APACHE_LOG_DIR}/openemr_fpm_error.log
    CustomLog \${APACHE_LOG_DIR}/openemr_fpm_access.log common
</VirtualHost>
APACHE_CONFIG_EOF

echo "✓ Configuration file created: ${CONF_FILE}"

# Set permissions for OpenEMR
echo "Setting file permissions for OpenEMR..."
mkdir -p "${OPENEMR_PATH}/sites/default/documents"
mkdir -p "${OPENEMR_PATH}/sites/default/edi"
mkdir -p "${OPENEMR_PATH}/sites/default/era"
mkdir -p "${OPENEMR_PATH}/sites/default/letter_templates"
mkdir -p "${OPENEMR_PATH}/gdata"
touch "${OPENEMR_PATH}/sites/default/sqlconf.php"

# Detect web user
WEB_USER="www-data"
if ! id "${WEB_USER}" >/dev/null 2>&1; then
    WEB_USER="openemr"
fi

chown -R ${WEB_USER}:${WEB_USER} "${OPENEMR_PATH}"
chmod 666 "${OPENEMR_PATH}/sites/default/sqlconf.php"
chmod 777 "${OPENEMR_PATH}/sites/default/documents"
chmod 777 "${OPENEMR_PATH}/sites/default/edi"
chmod 777 "${OPENEMR_PATH}/sites/default/era"
chmod 777 "${OPENEMR_PATH}/sites/default/letter_templates"
chmod 777 "${OPENEMR_PATH}/gdata"
echo "✓ Permissions updated"

# Enable required Apache modules
echo "Enabling required Apache modules..."
a2enmod rewrite proxy proxy_fcgi headers expires deflate

# Enable the site
echo "Enabling OpenEMR FPM site..."
a2ensite openemr-fpm

# Test configuration
echo "Testing Apache configuration..."
if apache2ctl configtest; then
    echo ""
    echo "✓ Configuration is valid!"
    echo ""
    echo "Next steps:"
    echo "  1. Start PHP-FPM using: ./run-fpm.sh"
    echo "  2. Restart Apache: sudo systemctl restart apache2"
    echo "  3. Visit: http://localhost/"
else
    echo "✗ Configuration test failed. Please check the errors above."
    exit 1
fi
