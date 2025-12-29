#!/bin/sh
# ==============================================================================
# OpenEMR Web Server for Native FreeBSD
# ==============================================================================
# Simple script to run OpenEMR on a FreeBSD system.
# Logic mirrors run-freebsd-vm.sh (the QEMU VM runner) which is tested working.
#
# Usage:
#   ./run-web-server.sh [port]
#
# Example:
#   ./run-web-server.sh 8080
#
# Default port: 8080
# ==============================================================================

cd "$(dirname "$0")"

# Find distribution directory (either current dir or dist/ or dist/openemr-*/)
DIST_DIR=""

# Search order:
# 1. Current directory (if it contains the binaries)
# 2. dist/ subdirectory (if it contains the binaries)
# 3. Inside any openemr-* directory within dist/
for search_path in "." "./dist"; do
    if [ -d "${search_path}" ]; then
        # Check for standard names or patterns
        if [ -f "${search_path}/php" ] || ls "${search_path}"/php-cli-*-freebsd-* >/dev/null 2>&1; then
            DIST_DIR="${search_path}"
            break
        fi
    fi
done

if [ -z "$DIST_DIR" ] && [ -d "./dist" ]; then
    for dir in ./dist/openemr-*/; do
        if [ -f "${dir}php" ] || ls "${dir}"/php-cli-*-freebsd-* >/dev/null 2>&1; then
            DIST_DIR="${dir%/}"
            break
        fi
    done
fi

if [ -z "$DIST_DIR" ]; then
    echo "ERROR: Cannot find PHP binary"
    echo "Checked: . , ./dist , ./dist/openemr-*/"
    echo "Please run this script from the project root or the extracted distribution directory."
    exit 1
fi

# Determine the actual PHP binary to use
PHP_BINARY=""
if [ -f "${DIST_DIR}/php" ]; then
    PHP_BINARY="./php"
else
    PHP_BINARY=$(find "${DIST_DIR}" -maxdepth 1 -type f -name "php-cli-*-freebsd-*" -perm +111 2>/dev/null | head -1)
    if [ -n "${PHP_BINARY}" ]; then
        PHP_BINARY="./$(basename "${PHP_BINARY}")"
    fi
fi

if [ -z "${PHP_BINARY}" ]; then
    echo "ERROR: PHP binary not found in ${DIST_DIR}"
    exit 1
fi

# Find the PHAR file
PHAR_FILE=""
if [ -f "${DIST_DIR}/openemr.phar" ]; then
    PHAR_FILE="openemr.phar"
else
    PHAR_FILE=$(find "${DIST_DIR}" -maxdepth 1 -type f -name "openemr-*.phar" 2>/dev/null | head -1)
    if [ -n "${PHAR_FILE}" ]; then
        PHAR_FILE="$(basename "${PHAR_FILE}")"
    fi
fi

if [ -z "${PHAR_FILE}" ]; then
    echo "ERROR: OpenEMR PHAR file not found in ${DIST_DIR}"
    exit 1
fi

cd "$DIST_DIR"

# Set library path for bundled shared libraries
# Libraries could be in ./lib or relative to PHP binary
if [ -d "./lib" ]; then
    export LD_LIBRARY_PATH="./lib:${LD_LIBRARY_PATH:-}"
fi

PORT="${1:-8080}"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  OpenEMR Web Server for FreeBSD"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  URL:     http://localhost:$PORT"
echo "  Binary:  ${PHP_BINARY}"
echo "  PHAR:    ${PHAR_FILE}"
echo "  Dir:     $(pwd)"
echo ""
echo "  Press Ctrl+C to stop"
echo ""
echo "════════════════════════════════════════════════════════════"
echo ""

exec "${PHP_BINARY}" -d memory_limit=512M -S 0.0.0.0:$PORT "${PHAR_FILE}"
