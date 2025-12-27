#!/bin/sh
# PHP CGI Wrapper Script for Apache on Linux (arm64)
# 
# This script is executed by Apache when a .php file is requested via CGI.
# It calls the PHP CGI binary with the requested script file.

# Set the path to your PHP CGI binary
if [ -z "${PHP_CGI_BINARY:-}" ]; then
    # Try to auto-detect the PHP CGI binary
    if [ -n "${DOCUMENT_ROOT:-}" ]; then
        PARENT_DIR="$(dirname "${DOCUMENT_ROOT}")"
        # Find php-cgi-*-linux-arm64 or php-cgi-linux-arm64 in parent directory
        PHP_CGI_BINARY=$(find "${PARENT_DIR}" -maxdepth 1 -type f \( -name "php-cgi-*-linux-arm64" -o -name "php-cgi-linux-arm64" \) -perm /111 2>/dev/null | head -1)
    fi
    
    # If still not found, try to find it relative to this script's location
    if [ -z "${PHP_CGI_BINARY:-}" ]; then
        SCRIPT_DIR="$(dirname "$0")"
        if [ -d "${SCRIPT_DIR}/../.." ]; then
            PARENT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
            PHP_CGI_BINARY=$(find "${PARENT_DIR}" -maxdepth 1 -type f \( -name "php-cgi-*-linux-arm64" -o -name "php-cgi-linux-arm64" \) -perm /111 2>/dev/null | head -1)
        fi
    fi
    
    if [ -z "${PHP_CGI_BINARY:-}" ] || [ ! -f "${PHP_CGI_BINARY}" ]; then
        echo "Status: 500 Internal Server Error"
        echo "Content-Type: text/plain"
        echo ""
        echo "Error: PHP CGI binary not found"
        echo "Please set PHP_CGI_BINARY environment variable or ensure php-cgi-*-linux-arm64 exists in the parent directory"
        exit 1
    fi
fi

# Determine which PHP file was requested
if [ -n "${SCRIPT_FILENAME:-}" ] && [ -f "${SCRIPT_FILENAME}" ]; then
    SCRIPT_FILE="${SCRIPT_FILENAME}"
elif [ -z "${DOCUMENT_ROOT:-}" ]; then
    echo "Status: 500 Internal Server Error"
    echo "Content-Type: text/plain"
    echo ""
    echo "Error: DOCUMENT_ROOT not set"
    exit 1
else
    REQUEST_PATH="${REQUEST_URI%%\?*}"
    REQUEST_PATH="${REQUEST_PATH%%#*}"
    if [ "${REQUEST_PATH}" = "/" ] || [ -z "${REQUEST_PATH}" ]; then
        REQUEST_PATH="/index.php"
    fi
    REQUEST_PATH="${REQUEST_PATH#/}"
    SCRIPT_FILE="${DOCUMENT_ROOT}/${REQUEST_PATH}"
fi

# PHP CGI requires REDIRECT_STATUS
export REDIRECT_STATUS="${REDIRECT_STATUS:-200}"

# Execute PHP CGI
exec "${PHP_CGI_BINARY}" "${SCRIPT_FILE}"
