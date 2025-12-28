#!/usr/bin/env bash
# Script to update Apache configuration with correct paths for PHP-FPM on FreeBSD
# Run with: sudo ./setup-apache-config.sh

set -e

# Auto-detect script directory and project paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FREEBSD_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
PROJECT_ROOT="$( cd "${FREEBSD_DIR}/.." && pwd )"
OPENEMR_PATH="${FREEBSD_DIR}/openemr-extracted"

# FreeBSD Apache configuration directory
if [ -d "/usr/local/etc/apache24" ]; then
    APACHE_CONF_DIR="/usr/local/etc/apache24"
    APACHE_EXTRA_DIR="${APACHE_CONF_DIR}/Includes"
    HTTPD_CONF="${APACHE_CONF_DIR}/httpd.conf"
    LOG_DIR="/var/log"
    # Ensure Includes directory exists
    mkdir -p "${APACHE_EXTRA_DIR}"
else
    echo "Error: Could not find Apache configuration directory at /usr/local/etc/apache24"
    exit 1
fi

CONF_FILE="${APACHE_EXTRA_DIR}/httpd-openemr-fpm.conf"

echo "Apache PHP-FPM Setup for OpenEMR on FreeBSD"
echo "=========================================="
echo "Script directory: ${SCRIPT_DIR}"
echo "OpenEMR path: ${OPENEMR_PATH}"
echo "Apache config: ${CONF_FILE}"
echo ""

# Verify OpenEMR directory exists
if [ ! -d "${OPENEMR_PATH}" ]; then
    echo "Error: OpenEMR directory not found at ${OPENEMR_PATH}"
    echo "Please extract OpenEMR first using: cd ${FREEBSD_DIR}/apache_fpm && ./extract-openemr.sh"
    exit 1
fi

# Create updated configuration file
echo "Creating Apache configuration file at ${CONF_FILE}..."
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
    
    echo "Checking module ${module_name}..."
    # Check if already enabled
    if grep -q "^LoadModule ${module_name}" "${HTTPD_CONF}"; then
        echo "✓ ${module_name} already enabled"
        return 0
    fi
    
    # Check if commented out and uncomment it
    if grep -q "^#LoadModule ${module_name}" "${HTTPD_CONF}"; then
        sed -i '' "s|^#LoadModule ${module_name}|LoadModule ${module_name}|g" "${HTTPD_CONF}"
        echo "✓ Enabled ${module_name}"
        return 0
    fi
    
    # If not found, add it
    echo "LoadModule ${module_name} ${module_file}" >> "${HTTPD_CONF}"
    echo "✓ Added ${module_name}"
}

# Enable required modules (paths are relative to /usr/local in FreeBSD)
enable_module "rewrite_module" "libexec/apache24/mod_rewrite.so"
enable_module "proxy_module" "libexec/apache24/mod_proxy.so"
enable_module "proxy_fcgi_module" "libexec/apache24/mod_proxy_fcgi.so"
enable_module "deflate_module" "libexec/apache24/mod_deflate.so"
enable_module "headers_module" "libexec/apache24/mod_headers.so"
enable_module "expires_module" "libexec/apache24/mod_expires.so"

echo "Repairing and setting main DocumentRoot to ${OPENEMR_PATH} in ${HTTPD_CONF}..."
# Use a very safe replacement that doesn't rely on start-of-line anchors
sed -i '' "s|\"/usr/local/www/apache24/data\"|\"${OPENEMR_PATH}\"|g" "${HTTPD_CONF}"

# Fix hostname warning for faster startup
echo "Fixing ServerName warning..."
if ! grep -q "^ServerName" "${HTTPD_CONF}"; then
    echo "ServerName 127.0.0.1:80" >> "${HTTPD_CONF}"
fi

echo "Removing default index.html to avoid 'It works!' page..."
rm -f /usr/local/www/apache24/data/index.html || true

echo ""

# Test configuration
echo "Testing Apache configuration..."
if apachectl configtest; then
    echo ""
    echo "✓ Configuration is valid!"
    echo ""
    echo "Next steps:"
    echo "  1. Start PHP-FPM using the run-fpm.sh script in this directory"
    echo "  2. Restart Apache: service apache24 restart"
    echo "  3. Visit: http://localhost/"
else
    echo "✗ Configuration test failed. Please check the errors above."
    exit 1
fi
