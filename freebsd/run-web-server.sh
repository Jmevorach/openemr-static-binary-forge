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

# Find distribution directory (either current dir or dist/openemr-*/)
if [ -f "./php" ] && [ -f "./openemr.phar" ]; then
    DIST_DIR="."
elif [ -d "./dist" ]; then
    for dir in ./dist/openemr-*-freebsd-*/; do
        if [ -f "${dir}php" ]; then
            DIST_DIR="${dir%/}"
            break
        fi
    done
fi

if [ -z "$DIST_DIR" ] || [ ! -f "${DIST_DIR}/php" ]; then
    echo "ERROR: Cannot find php binary"
    echo "Run this script from the extracted distribution directory,"
    echo "or ensure dist/openemr-*-freebsd-*/ exists."
    exit 1
fi

cd "$DIST_DIR"

# Set library path for bundled shared libraries
export LD_LIBRARY_PATH="./lib:${LD_LIBRARY_PATH:-}"

PORT="${1:-8080}"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  OpenEMR Web Server for FreeBSD"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  URL:  http://localhost:$PORT"
echo "  Dir:  $(pwd)"
echo ""
echo "  Press Ctrl+C to stop"
echo ""
echo "════════════════════════════════════════════════════════════"
echo ""

exec ./php -d memory_limit=512M -S 0.0.0.0:$PORT openemr.phar
