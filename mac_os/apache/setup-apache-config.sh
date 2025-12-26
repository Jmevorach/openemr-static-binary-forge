#!/bin/bash
# Script to update Apache configuration with correct paths and port
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
elif [ -d "/usr/local/etc/httpd" ]; then
    # Intel Mac Homebrew
    APACHE_EXTRA_DIR="/usr/local/etc/httpd/extra"
    HTTPD_CONF="/usr/local/etc/httpd/httpd.conf"
elif [ -d "/private/etc/apache2" ]; then
    # System Apache
    APACHE_EXTRA_DIR="/private/etc/apache2/extra"
    HTTPD_CONF="/private/etc/apache2/httpd.conf"
else
    echo "Error: Could not find Apache configuration directory"
    exit 1
fi

CONF_FILE="${APACHE_EXTRA_DIR}/httpd-openemr.conf"

echo "Apache CGI Setup for OpenEMR"
echo "=============================="
echo "Script directory: ${SCRIPT_DIR}"
echo "OpenEMR path: ${OPENEMR_PATH}"
echo "Apache config: ${CONF_FILE}"
echo ""

# Verify OpenEMR directory exists
if [ ! -d "${OPENEMR_PATH}" ]; then
    echo "Error: OpenEMR directory not found at ${OPENEMR_PATH}"
    echo "Please extract OpenEMR first using: cd ${MAC_OS_DIR} && ./apache/extract-openemr.sh"
    exit 1
fi

# Verify PHP CGI binary exists (wrapper script will auto-detect it)
PHP_CGI=$(find "${MAC_OS_DIR}" -maxdepth 1 -type f -name "php-cgi-*-macos-*" -perm +111 2>/dev/null | head -1)
if [ -z "${PHP_CGI:-}" ] || [ ! -f "${PHP_CGI}" ]; then
    echo "Warning: PHP CGI binary not found at ${MAC_OS_DIR}/php-cgi-*-macos-*"
    echo "The wrapper script will try to auto-detect it, but you may need to run:"
    echo "  cd ${MAC_OS_DIR} && ./build-macos.sh"
    echo ""
else
    echo "✓ Found PHP CGI binary: $(basename "${PHP_CGI}")"
fi

# Ensure cgi-bin directory exists
if [ ! -d "${OPENEMR_PATH}/cgi-bin" ]; then
    echo "Creating cgi-bin directory..."
    mkdir -p "${OPENEMR_PATH}/cgi-bin"
fi

# Copy and configure wrapper script if it doesn't exist or needs updating
WRAPPER_SCRIPT="${OPENEMR_PATH}/cgi-bin/php-wrapper.cgi"
WRAPPER_TEMPLATE="${SCRIPT_DIR}/php-wrapper.sh"

if [ ! -f "${WRAPPER_SCRIPT}" ] || [ "${WRAPPER_TEMPLATE}" -nt "${WRAPPER_SCRIPT}" ]; then
    echo "Setting up PHP wrapper script..."
    cp "${WRAPPER_TEMPLATE}" "${WRAPPER_SCRIPT}"
    chmod +x "${WRAPPER_SCRIPT}"
    echo "✓ Wrapper script installed: ${WRAPPER_SCRIPT}"
fi

# Create updated configuration file
cat > "${CONF_FILE}" << 'APACHE_CONFIG_EOF'
# Apache Virtual Host Configuration for OpenEMR
# 
# This configuration uses the static PHP CGI binary to execute PHP files via a wrapper script.

# Paths - automatically configured
Define OPENEMR_PATH OPENEMR_PATH_PLACEHOLDER

<VirtualHost *:8080>
    ServerName localhost
    DocumentRoot "${OPENEMR_PATH}"
    
    # Optional: Enable debug mode for the PHP wrapper script (1 to enable)
    # SetEnv DEBUG_PHP_WRAPPER 1
    
    # Enable mod_rewrite for redirects
    RewriteEngine On
    
    # Redirect root to index.php if no file is specified
    RewriteRule ^$ /index.php [L]
    
    # Configure ScriptAlias for cgi-bin directory (needed for Action directive)
    # The second argument to Action MUST be a URL path, not a file path
    ScriptAlias /cgi-bin/ "${OPENEMR_PATH}/cgi-bin/"
    
    <Directory "${OPENEMR_PATH}/cgi-bin">
        Options +ExecCGI
        Require all granted
    </Directory>

    # Use Action directive to map .php files to the wrapper script
    Action application/x-httpd-php /cgi-bin/php-wrapper.cgi
    AddHandler application/x-httpd-php .php
    
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
    <Directory "${OPENEMR_PATH}">
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
        
        # Security: Prevent access to sensitive files
        <FilesMatch "\.(git|sql|ini|log|json|lock|md)$">
            Require all denied
        </FilesMatch>
        
        # Deny access to hidden files
        <FilesMatch "^\.">
            Require all denied
        </FilesMatch>
    </Directory>
    
    # Allow CGI execution for the wrapper script
    <FilesMatch "php-wrapper\.cgi$">
        Options +ExecCGI
        Require all granted
        SetHandler cgi-script
    </FilesMatch>
    
    # Static file handling
    <FilesMatch "\.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$">
        ExpiresActive On
        ExpiresDefault "access plus 1 year"
    </FilesMatch>
    
    # Security headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    
    # Logging
    ErrorLog "/opt/homebrew/var/log/httpd/openemr_error.log"
    CustomLog "/opt/homebrew/var/log/httpd/openemr_access.log" common
</VirtualHost>
APACHE_CONFIG_EOF

# Replace OPENEMR_PATH placeholder with actual path
sed -i '' "s|OPENEMR_PATH_PLACEHOLDER|${OPENEMR_PATH}|g" "${CONF_FILE}"

echo "✓ Configuration file updated: ${CONF_FILE}"
echo "  Note: PHP CGI binary will be auto-detected by the wrapper script"

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
        # Uncomment the module (macOS sed requires backup extension, use empty string)
        sed -i '' "s|^#LoadModule ${module_name} ${module_file}|LoadModule ${module_name} ${module_file}|g" "${HTTPD_CONF}"
        echo "✓ Enabled ${module_name}"
        return 0
    fi
    
    # If not found, add it
    echo "LoadModule ${module_name} ${module_file}" >> "${HTTPD_CONF}"
    echo "✓ Added ${module_name}"
}

# Enable mod_rewrite (for root redirect)
enable_module "rewrite_module" "lib/httpd/modules/mod_rewrite.so"

# Enable mod_actions (required for Action directive)
enable_module "actions_module" "lib/httpd/modules/mod_actions.so"

# Enable mod_deflate (for compression)
enable_module "deflate_module" "lib/httpd/modules/mod_deflate.so"

# Enable mod_cgi
enable_module "cgi_module" "lib/httpd/modules/mod_cgi.so"

# Enable mod_headers (for security headers)
enable_module "headers_module" "lib/httpd/modules/mod_headers.so"

# Enable mod_expires (for static file caching)
enable_module "expires_module" "lib/httpd/modules/mod_expires.so"

echo ""

# Add Include directive to httpd.conf if not present
if ! grep -q "Include.*extra/httpd-openemr.conf" "${HTTPD_CONF}"; then
    echo "" >> "${HTTPD_CONF}"
    echo "# OpenEMR configuration" >> "${HTTPD_CONF}"
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
    echo "  1. Restart Apache: brew services restart httpd"
    echo "  2. Test: curl http://localhost:8080/test.php"
    echo "  3. Or visit: http://localhost:8080/"
else
    echo "✗ Configuration test failed. Please check the errors above."
    exit 1
fi

