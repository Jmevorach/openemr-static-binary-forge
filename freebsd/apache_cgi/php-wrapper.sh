#!/bin/sh
# PHP CGI Wrapper Script for Apache on FreeBSD
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

# Set the path to your PHP CGI binary
# Can be set via PHP_CGI_BINARY environment variable, or will be auto-detected
if [ -z "${PHP_CGI_BINARY:-}" ]; then
    # Try to auto-detect the PHP CGI binary
    # Look in parent directory of DOCUMENT_ROOT (typically freebsd directory)
    if [ -n "${DOCUMENT_ROOT:-}" ]; then
        PARENT_DIR="$(dirname "${DOCUMENT_ROOT}")"
        
        # 1. Try common standalone names (from dist/ folder or parent)
        for search_path in "${PARENT_DIR}/dist" "${PARENT_DIR}"; do
            if [ -d "${search_path}" ]; then
                PHP_CGI_BINARY=$(find "${search_path}" -maxdepth 1 -type f -name "php-cgi-*-freebsd-*" -perm +111 2>/dev/null | head -1)
                [ -n "${PHP_CGI_BINARY}" ] && break
            fi
        done
        
        # 2. Try standard bin/php-cgi path (from tarball extraction)
        if [ -z "${PHP_CGI_BINARY}" ]; then
            for search_path in "${PARENT_DIR}/dist" "${PARENT_DIR}"; do
                if [ -f "${search_path}/bin/php-cgi" ]; then
                    PHP_CGI_BINARY="${search_path}/bin/php-cgi"
                    break
                fi
            done
        fi
    fi
    
    # If still not found, try to find it relative to this script's location
    if [ -z "${PHP_CGI_BINARY:-}" ]; then
        SCRIPT_DIR="$(dirname "$0")"
        # Go up from cgi-bin to openemr-extracted, then to parent (freebsd)
        if [ -d "${SCRIPT_DIR}/../.." ]; then
            PARENT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
            
            # 1. Try common standalone names
            for search_path in "${PARENT_DIR}/dist" "${PARENT_DIR}"; do
                if [ -d "${search_path}" ]; then
                    PHP_CGI_BINARY=$(find "${search_path}" -maxdepth 1 -type f -name "php-cgi-*-freebsd-*" -perm +111 2>/dev/null | head -1)
                    [ -n "${PHP_CGI_BINARY}" ] && break
                fi
            done
            
            # 2. Try standard bin/php-cgi path
            if [ -z "${PHP_CGI_BINARY}" ]; then
                for search_path in "${PARENT_DIR}/dist" "${PARENT_DIR}"; do
                    if [ -f "${search_path}/bin/php-cgi" ]; then
                        PHP_CGI_BINARY="${search_path}/bin/php-cgi"
                        break
                    fi
                done
            fi
        fi
    fi
    
    # If still not found, error out
    if [ -z "${PHP_CGI_BINARY:-}" ] || [ ! -f "${PHP_CGI_BINARY}" ]; then
        echo "Status: 500 Internal Server Error"
        echo "Content-Type: text/plain"
        echo ""
        echo "Error: PHP CGI binary not found"
        echo "Please set PHP_CGI_BINARY environment variable or ensure php-cgi-*-freebsd-* exists in the parent or dist/ directory"
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
    # Fallback: Extract path from REQUEST_URI
    REQUEST_PATH="${REQUEST_URI%%\?*}"
    REQUEST_PATH="${REQUEST_PATH%%#*}"

    if [ "${REQUEST_PATH}" = "/" ] || [ -z "${REQUEST_PATH}" ]; then
        REQUEST_PATH="/index.php"
    fi

    REQUEST_PATH="${REQUEST_PATH#/}"

    # Security: Prevent path traversal
    case "${REQUEST_PATH}" in
        *..*|*/../*|*\\.\\*)
            echo "Status: 403 Forbidden"
            echo "Content-Type: text/plain"
            echo ""
            echo "Error: Invalid path (path traversal attempt detected)"
            exit 1
            ;;
    esac

    SCRIPT_FILE="${DOCUMENT_ROOT}/${REQUEST_PATH}"
fi

# Resolve to absolute path and verify it's within DOCUMENT_ROOT
CANONICAL_DOCROOT="$(cd "${DOCUMENT_ROOT}" 2>/dev/null && pwd)"
if [ -z "${CANONICAL_DOCROOT}" ]; then
    echo "Status: 500 Internal Server Error"
    echo "Content-Type: text/plain"
    echo ""
    echo "Error: Invalid DOCUMENT_ROOT"
    exit 1
fi

SCRIPT_DIR_PATH="$(dirname "${SCRIPT_FILE}")"
SCRIPT_BASE="$(basename "${SCRIPT_FILE}")"
CANONICAL_SCRIPT_DIR="$(cd "${SCRIPT_DIR_PATH}" 2>/dev/null && pwd)"
if [ -z "${CANONICAL_SCRIPT_DIR}" ]; then
    echo "Status: 404 Not Found"
    echo "Content-Type: text/plain"
    echo ""
    echo "Error: Script directory not found"
    exit 1
fi
CANONICAL_SCRIPT="${CANONICAL_SCRIPT_DIR}/${SCRIPT_BASE}"

case "${CANONICAL_SCRIPT}" in
    "${CANONICAL_DOCROOT}"/*)
        SCRIPT_FILE="${CANONICAL_SCRIPT}"
        ;;
    *)
        echo "Status: 403 Forbidden"
        echo "Content-Type: text/plain"
        echo ""
        echo "Error: Invalid path (outside document root)"
        exit 1
        ;;
esac

if [ ! -f "${SCRIPT_FILE}" ]; then
    echo "Status: 404 Not Found"
    echo "Content-Type: text/plain"
    echo ""
    echo "Error: PHP script file not found"
    exit 1
fi

# PHP CGI requires REDIRECT_STATUS
export REDIRECT_STATUS="${REDIRECT_STATUS:-200}"

# Execute PHP CGI
# Set library path for bundled libraries if they exist
# We check parent directory and dist directory for lib/
PHP_CGI_DIR="$(dirname "${PHP_CGI_BINARY}")"
# If binary is in dist/bin/php-cgi, libraries are in dist/lib/
# If binary is in dist/php-cgi-..., libraries are in dist/lib/
if [[ "${PHP_CGI_DIR}" == */bin ]]; then
    LIB_DIR="$(dirname "${PHP_CGI_DIR}")/lib"
else
    LIB_DIR="${PHP_CGI_DIR}/lib"
fi

export LD_LIBRARY_PATH="${LIB_DIR}:/usr/local/lib:${LD_LIBRARY_PATH:-}"
exec "${PHP_CGI_BINARY}" "${SCRIPT_FILE}"
