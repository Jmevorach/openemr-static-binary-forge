#!/bin/sh
# PHP CGI Wrapper Script for Apache
# 
# This script is executed by Apache when a .php file is requested via CGI.
# It calls the PHP CGI binary with the requested script file.
#
# Setup:
# 1. Copy this file to: ${OPENEMR_PATH}/cgi-bin/php-wrapper.cgi
# 2. Make it executable: chmod +x ${OPENEMR_PATH}/cgi-bin/php-wrapper.cgi
#
# The PHP CGI binary will be auto-detected. To override, set PHP_CGI_BINARY
# environment variable in your Apache VirtualHost configuration.
#
# The script receives the script file path via SCRIPT_NAME (from ScriptAliasMatch)
# or REQUEST_URI environment variables.

# Set the path to your PHP CGI binary
# Can be set via PHP_CGI_BINARY environment variable, or will be auto-detected
if [ -z "${PHP_CGI_BINARY:-}" ]; then
    # Try to auto-detect the PHP CGI binary
    # Look in parent directory of DOCUMENT_ROOT (typically mac_os directory)
    if [ -n "${DOCUMENT_ROOT:-}" ]; then
        PARENT_DIR="$(dirname "${DOCUMENT_ROOT}")"
        # Find php-cgi-*-macos-* in parent directory
        PHP_CGI_BINARY=$(find "${PARENT_DIR}" -maxdepth 1 -type f -name "php-cgi-*-macos-*" -perm +111 2>/dev/null | head -1)
    fi
    
    # If still not found, try to find it relative to this script's location
    if [ -z "${PHP_CGI_BINARY:-}" ]; then
        SCRIPT_DIR="$(dirname "$0")"
        # Go up from cgi-bin to openemr-extracted, then to parent (mac_os)
        if [ -d "${SCRIPT_DIR}/../.." ]; then
            PARENT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
            PHP_CGI_BINARY=$(find "${PARENT_DIR}" -maxdepth 1 -type f -name "php-cgi-*-macos-*" -perm +111 2>/dev/null | head -1)
        fi
    fi
    
    # If still not found, error out
    if [ -z "${PHP_CGI_BINARY:-}" ] || [ ! -f "${PHP_CGI_BINARY}" ]; then
        echo "Status: 500 Internal Server Error"
        echo "Content-Type: text/plain"
        echo ""
        echo "Error: PHP CGI binary not found"
        echo "Please set PHP_CGI_BINARY environment variable or ensure php-cgi-*-macos-* exists in the parent directory"
        exit 1
    fi
fi

# This wrapper script is called via Action directive when a .php file is requested
# SCRIPT_FILENAME contains the path to the actual PHP file that was requested
# REQUEST_URI contains the original request path (e.g., /test.php)

# Determine which PHP file was requested
# When using Action directive, SCRIPT_FILENAME contains the path to the PHP file
if [ -n "${SCRIPT_FILENAME:-}" ] && [ -f "${SCRIPT_FILENAME}" ]; then
    SCRIPT_FILE="${SCRIPT_FILENAME}"
elif [ -z "${DOCUMENT_ROOT:-}" ]; then
    echo "Status: 500 Internal Server Error"
    echo "Content-Type: text/plain"
    echo ""
    echo "Error: DOCUMENT_ROOT not set"
    exit 1
elif [ -z "${REQUEST_URI:-}" ]; then
    echo "Status: 500 Internal Server Error"
    echo "Content-Type: text/plain"
    echo ""
    echo "Error: REQUEST_URI not set"
    exit 1
else
    # Fallback: Extract path from REQUEST_URI
    REQUEST_PATH="${REQUEST_URI%%\?*}"
    REQUEST_PATH="${REQUEST_PATH%%#*}"

    # Handle root path - map to index.php
    if [ "${REQUEST_PATH}" = "/" ] || [ -z "${REQUEST_PATH}" ]; then
        REQUEST_PATH="/index.php"
    fi

    # Remove leading slash (after handling root case)
    REQUEST_PATH="${REQUEST_PATH#/}"

    # Security: Prevent path traversal attacks
    # Check for ../ or ..\ patterns (case insensitive)
    case "${REQUEST_PATH}" in
        *..*|*/../*|*\\.\\*)
            echo "Status: 403 Forbidden"
            echo "Content-Type: text/plain"
            echo ""
            echo "Error: Invalid path (path traversal attempt detected)"
            exit 1
            ;;
    esac

    # Combine with DOCUMENT_ROOT
    SCRIPT_FILE="${DOCUMENT_ROOT}/${REQUEST_PATH}"
fi

# Security: Resolve to absolute path and verify it's within DOCUMENT_ROOT
# This prevents symlink attacks and ensures the file is within the document root
CANONICAL_DOCROOT="$(cd "${DOCUMENT_ROOT}" 2>/dev/null && pwd)"
if [ -z "${CANONICAL_DOCROOT}" ]; then
    echo "Status: 500 Internal Server Error"
    echo "Content-Type: text/plain"
    echo ""
    echo "Error: Invalid DOCUMENT_ROOT"
    exit 1
fi

# Get canonical path of the script file
SCRIPT_DIR="$(dirname "${SCRIPT_FILE}")"
SCRIPT_BASE="$(basename "${SCRIPT_FILE}")"
CANONICAL_SCRIPT_DIR="$(cd "${SCRIPT_DIR}" 2>/dev/null && pwd)"
if [ -z "${CANONICAL_SCRIPT_DIR}" ]; then
    echo "Status: 404 Not Found"
    echo "Content-Type: text/plain"
    echo ""
    echo "Error: Script directory not found"
    exit 1
fi
CANONICAL_SCRIPT="${CANONICAL_SCRIPT_DIR}/${SCRIPT_BASE}"

# Check if the canonical path starts with the canonical document root
case "${CANONICAL_SCRIPT}" in
    "${CANONICAL_DOCROOT}"/*)
        # Path is within document root, use canonical path
        SCRIPT_FILE="${CANONICAL_SCRIPT}"
        ;;
    *)
        # Path is outside document root - security violation
        echo "Status: 403 Forbidden"
        echo "Content-Type: text/plain"
        echo ""
        echo "Error: Invalid path (outside document root)"
        exit 1
        ;;
esac

# Verify the script file exists and is a regular file
if [ ! -f "${SCRIPT_FILE}" ]; then
    echo "Status: 404 Not Found"
    echo "Content-Type: text/plain"
    echo ""
    echo "Error: PHP script file not found"
    exit 1
fi

# Verify it's a PHP file (additional safety check)
# Allow .php extension or no extension (if it's a valid file)
case "${SCRIPT_FILE}" in
    *.php|*.php?*|*.php#*)
        # Valid PHP extension
        ;;
    *)
        # If it doesn't have .php extension, check if it's actually a PHP file
        # This handles cases where the path might not have an extension but points to a PHP script
        if ! grep -q "<?php" "${SCRIPT_FILE}" 2>/dev/null; then
            echo "Status: 403 Forbidden"
            echo "Content-Type: text/plain"
            echo ""
            echo "Error: File is not a PHP script (${SCRIPT_FILE})"
            exit 1
        fi
        ;;
esac

# PHP CGI requires REDIRECT_STATUS to be set (force-cgi-redirect security feature)
# If not already set by Apache, set it to 200 (OK status)
export REDIRECT_STATUS="${REDIRECT_STATUS:-200}"

# Debug logging (enable by setting DEBUG_PHP_WRAPPER=1 in Apache)
if [ "${DEBUG_PHP_WRAPPER:-0}" = "1" ]; then
    echo "Status: 200 OK"
    echo "Content-Type: text/plain"
    echo ""
    echo "--- Debug Information ---"
    echo "PHP_CGI_BINARY: ${PHP_CGI_BINARY}"
    echo "DOCUMENT_ROOT: ${DOCUMENT_ROOT}"
    echo "REQUEST_URI: ${REQUEST_URI}"
    echo "SCRIPT_FILENAME: ${SCRIPT_FILENAME:-not set}"
    echo "SCRIPT_NAME: ${SCRIPT_NAME:-not set}"
    echo "PATH_INFO: ${PATH_INFO:-not set}"
    echo "REQUEST_PATH: ${REQUEST_PATH:-not set}"
    echo "SCRIPT_FILE: ${SCRIPT_FILE}"
    echo "--------------------------"
    exit 0
fi

# Execute PHP CGI with the script file
exec "${PHP_CGI_BINARY}" "${SCRIPT_FILE}"
