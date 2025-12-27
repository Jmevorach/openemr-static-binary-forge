#!/bin/bash
# Script to update Apache configuration with correct paths for PHP-FPM
# Run with: sudo ./setup-apache-config.sh

set -e

# Auto-detect script directory and project paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MAC_OS_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
PROJECT_ROOT="$( cd "${MAC_OS_DIR}/.." && pwd )"
OPENEMR_PATH="${MAC_OS_DIR}/openemr-extracted"

# Auto-detect Apache configuration directory
if [ -d "/opt/homebrew/etc/httpd" ]; then
    # Apple Silicon Homebrew
    APACHE_EXTRA_DIR="/opt/homebrew/etc/httpd/extra"
    HTTPD_CONF="/opt/homebrew/etc/httpd/httpd.conf"
    LOG_DIR="/opt/homebrew/var/log/httpd"
elif [ -d "/usr/local/etc/httpd" ]; then
    # Intel Mac Homebrew
    APACHE_EXTRA_DIR="/usr/local/etc/httpd/extra"
    HTTPD_CONF="/usr/local/etc/httpd/httpd.conf"
    LOG_DIR="/usr/local/var/log/httpd"
elif [ -d "/private/etc/apache2" ]; then
    # System Apache
    APACHE_EXTRA_DIR="/private/etc/apache2/extra"
    HTTPD_CONF="/private/etc/apache2/httpd.conf"
    LOG_DIR="/var/log/apache2"
else
    echo "Error: Could not find Apache configuration directory"
    exit 1
fi

CONF_FILE="${APACHE_EXTRA_DIR}/httpd-openemr-fpm.conf"

echo "Apache PHP-FPM Setup for OpenEMR"
echo "================================="
echo "Script directory: ${SCRIPT_DIR}"
echo "OpenEMR path: ${OPENEMR_PATH}"
echo "Apache config: ${CONF_FILE}"
echo ""

# Verify OpenEMR directory exists
if [ ! -d "${OPENEMR_PATH}" ]; then
    echo "Error: OpenEMR directory not found at ${OPENEMR_PATH}"
    echo "Please extract OpenEMR first using: cd ${MAC_OS_DIR}/apache_fpm && ./extract-openemr.sh"
    exit 1
fi

# Verify PHP FPM binary exists
PHP_FPM=$(find "${MAC_OS_DIR}" -maxdepth 1 -type f -name "php-fpm-*-macos-*" -perm +111 2>/dev/null | head -1)
if [ -z "${PHP_FPM:-}" ] || [ ! -f "${PHP_FPM}" ]; then
    echo "Warning: PHP FPM binary not found at ${MAC_OS_DIR}/php-fpm-*-macos-*"
    echo "You may need to run: cd ${MAC_OS_DIR} && ./build-macos.sh"
    echo ""
else
    echo "✓ Found PHP FPM binary: $(basename "${PHP_FPM}")"
fi

# Create updated configuration file
cat > "${CONF_FILE}" << APACHE_CONFIG_EOF
# Apache Virtual Host Configuration for OpenEMR (PHP-FPM)
# 
# This configuration uses PHP-FPM via mod_proxy_fcgi to execute PHP files.

# Paths - automatically configured
Define OPENEMR_PATH ${OPENEMR_PATH}

<VirtualHost *:8080>
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
    ErrorLog "${LOG_DIR}/openemr_fpm_error.log"
    CustomLog "${LOG_DIR}/openemr_fpm_access.log" common
</VirtualHost>
APACHE_CONFIG_EOF

echo "✓ Configuration file updated: ${CONF_FILE}"

# Enable required Apache modules
echo "Enabling required Apache modules..."

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

# Enable required modules
enable_module "rewrite_module" "lib/httpd/modules/mod_rewrite.so"
enable_module "proxy_module" "lib/httpd/modules/mod_proxy.so"
enable_module "proxy_fcgi_module" "lib/httpd/modules/mod_proxy_fcgi.so"
enable_module "deflate_module" "lib/httpd/modules/mod_deflate.so"
enable_module "headers_module" "lib/httpd/modules/mod_headers.so"
enable_module "expires_module" "lib/httpd/modules/mod_expires.so"

echo ""

# Add Include directive to httpd.conf if not present
if ! grep -q "Include.*extra/httpd-openemr-fpm.conf" "${HTTPD_CONF}"; then
    echo "" >> "${HTTPD_CONF}"
    echo "# OpenEMR PHP-FPM configuration" >> "${HTTPD_CONF}"
    echo "Include ${CONF_FILE}" >> "${HTTPD_CONF}"
    echo "✓ Added Include directive to ${HTTPD_CONF}"
else
    echo "✓ Include directive already present in ${HTTPD_CONF}"
fi

# Test configuration
echo ""
echo "Testing Apache configuration..."
if apachectl configtest; then
    echo ""
    echo "✓ Configuration is valid!"
    echo ""
    echo "Next steps:"
    echo "  1. Start PHP-FPM using the run-fpm.sh script in this directory"
    echo "  2. Restart Apache: brew services restart httpd"
    echo "  3. Visit: http://localhost:8080/"
else
    echo "✗ Configuration test failed. Please check the errors above."
    exit 1
fi
