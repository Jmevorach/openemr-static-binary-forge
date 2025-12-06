#!/bin/sh
# Docker entrypoint script for OpenEMR static binary
# This script extracts the PHAR and runs PHP's built-in web server

set -e

PORT="${OPENEMR_PORT:-8080}"
WEB_ROOT="/app/openemr-extracted"
PHAR_FILE="/usr/local/share/openemr.phar"
PHP_BIN="/usr/local/bin/php"
TMP_DIR="/tmp"

# Ensure tmp directory exists and is writable
mkdir -p "${TMP_DIR}"
chmod 1777 "${TMP_DIR}" 2>/dev/null || true

# Extract PHAR if not already extracted
if [ ! -d "${WEB_ROOT}" ] || [ -z "$(ls -A ${WEB_ROOT} 2>/dev/null)" ]; then
    echo "Extracting OpenEMR from PHAR archive..."
    
    # Extract to temporary location first (writable by user)
    TEMP_EXTRACT="/tmp/openemr-extract-temp"
    mkdir -p "${TEMP_EXTRACT}"
    
    # Create extraction script
    cat > /tmp/extract.php << 'EOF'
<?php
ini_set('memory_limit', '1024M');
ini_set('max_execution_time', '0');
$pharFile = $argv[1];
$extractDir = $argv[2];
try {
    $phar = new Phar($pharFile);
    $phar->extractTo($extractDir, null, true);
    echo "Extracted successfully\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
    exit(1);
}
EOF
    
    # Extract to temp location using PHP CLI
    "${PHP_BIN}" -d memory_limit=1024M -d max_execution_time=0 /tmp/extract.php "${PHAR_FILE}" "${TEMP_EXTRACT}"
    rm -f /tmp/extract.php
    
    # Ensure destination directory exists and is writable
    mkdir -p "${WEB_ROOT}"
    
    # Copy from temp to final location
    echo "Copying extracted files to persistent volume..."
    cp -r "${TEMP_EXTRACT}"/* "${WEB_ROOT}"/ 2>/dev/null || {
        # If cp fails, try rsync or move
        if command -v rsync >/dev/null 2>&1; then
            rsync -a "${TEMP_EXTRACT}"/ "${WEB_ROOT}"/
        else
            # Fallback: move files one by one (slower but works)
            find "${TEMP_EXTRACT}" -mindepth 1 -maxdepth 1 -exec cp -r {} "${WEB_ROOT}"/ \;
        fi
    }
    
    # Clean up temp directory
    rm -rf "${TEMP_EXTRACT}"
    echo "OpenEMR extracted successfully"
fi

# Create router script for PHP built-in server
cat > /tmp/router.php << 'ROUTER'
<?php
$webRoot = getenv('OPENEMR_WEB_ROOT');
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$requestFile = $webRoot . $uri;

if ($uri !== '/' && file_exists($requestFile) && !is_dir($requestFile)) {
    return false;
}

$openemrEntryPoints = [
    $webRoot . '/interface/main/main.php',
    $webRoot . '/interface/main.php',
    $webRoot . '/main.php',
    $webRoot . '/index.php',
];

if (is_dir($webRoot)) {
    $interfaceDir = $webRoot . '/interface';
    if (is_dir($interfaceDir)) {
        if (is_dir($interfaceDir . '/main')) {
            $openemrEntryPoints[] = $interfaceDir . '/main/main.php';
            $openemrEntryPoints[] = $interfaceDir . '/main/index.php';
        }
        $openemrEntryPoints[] = $interfaceDir . '/main.php';
        $openemrEntryPoints[] = $interfaceDir . '/index.php';
    }
}

foreach ($openemrEntryPoints as $entryPoint) {
    if (file_exists($entryPoint)) {
        $_SERVER['SCRIPT_NAME'] = $entryPoint;
        $_SERVER['PHP_SELF'] = $entryPoint;
        $_SERVER['DOCUMENT_ROOT'] = $webRoot;
        require $entryPoint;
        return;
    }
}

http_response_code(404);
echo "OpenEMR entry point not found. Expected: interface/main/main.php\n";
echo "Web root: " . $webRoot . "\n";
ROUTER

export OPENEMR_WEB_ROOT="${WEB_ROOT}"
cd "${WEB_ROOT}"

# Check if php.ini exists and use it
PHP_INI_FILE="/usr/local/etc/php/php.ini"
PHP_INI_ARGS=""
if [ -f "${PHP_INI_FILE}" ]; then
    PHP_INI_ARGS="-c ${PHP_INI_FILE}"
    echo "Using PHP configuration from: ${PHP_INI_FILE}"
else
    echo "No custom php.ini found, using PHP defaults"
fi

echo "Starting OpenEMR web server on port ${PORT}..."
echo "OpenEMR will be available at http://localhost:${PORT}"

# Start PHP built-in server with php.ini if available
exec "${PHP_BIN}" ${PHP_INI_ARGS} -S "0.0.0.0:${PORT}" -t "${WEB_ROOT}" /tmp/router.php

