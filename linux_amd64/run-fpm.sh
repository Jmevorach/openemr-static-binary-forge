#!/usr/bin/env bash
# ==============================================================================
# OpenEMR PHP-FPM Runner (Linux amd64)
# ==============================================================================
# Helper script to run the static PHP-FPM binary on Linux.
#
# Usage:
#   ./run-fpm.sh
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Find the PHP FPM binary
PHP_FPM_BINARY=""

# 1. Check for standard system path (Docker setup)
if [ -f "/usr/local/bin/php-fpm" ] && [ -x "/usr/local/bin/php-fpm" ]; then
    PHP_FPM_BINARY="/usr/local/bin/php-fpm"
fi

# 2. Try common standalone names in current directory
if [ -z "${PHP_FPM_BINARY}" ]; then
    PHP_FPM_PATTERN="php-fpm-*-linux-amd64"
    PHP_FPM_BINARY=$(find "${SCRIPT_DIR}" -maxdepth 1 -type f \( -name "${PHP_FPM_PATTERN}" -o -name "php-fpm-linux-amd64" \) 2>/dev/null | head -1)
    
    # Verify it's executable
    if [ -n "${PHP_FPM_BINARY}" ] && [ ! -x "${PHP_FPM_BINARY}" ]; then
        PHP_FPM_BINARY=""
    fi
fi

if [ -z "${PHP_FPM_BINARY}" ]; then
    echo -e "${RED}ERROR: PHP FPM binary not found${NC}"
    echo "Checked: /usr/local/bin/php-fpm and ${SCRIPT_DIR}/php-fpm-*-linux-amd64"
    echo ""
    echo "Please build the binary first using: ./build-linux.sh"
    exit 1
fi

# Check for php.ini
PHP_INI="${SCRIPT_DIR}/php.ini"
PHP_INI_OPT=""
if [ -f "${PHP_INI}" ]; then
    PHP_INI_OPT="-c ${PHP_INI}"
fi

# Find FPM config
FPM_CONF="${SCRIPT_DIR}/apache_fpm/php-fpm.conf"
if [ ! -f "${FPM_CONF}" ]; then
    echo -e "${RED}ERROR: PHP-FPM config not found at ${FPM_CONF}${NC}"
    exit 1
fi

echo -e "${GREEN}Starting PHP-FPM (Linux amd64)...${NC}"
echo "Binary: $(basename "${PHP_FPM_BINARY}")"
echo "Config: ${FPM_CONF}"

# Run PHP-FPM
# -y: path to fpm conf
# -c: path to php.ini (if provided)
# -R: allow running as root
# -D: daemonize (run in background)
"${PHP_FPM_BINARY}" -y "${FPM_CONF}" ${PHP_INI_OPT} -R -D

echo -e "${GREEN}✓ PHP-FPM started successfully in the background${NC}"
echo "To stop PHP-FPM, run: pkill -f $(basename "${PHP_FPM_BINARY}")"

