#!/usr/bin/env bash
# Script to run PHP-FPM with the static binary on Linux
# To be used within the Docker container

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PHP_FPM_BINARY="/usr/local/bin/php-fpm"
FPM_CONF="/app/apache_fpm/php-fpm.conf"
PHP_INI="/usr/local/etc/php/php.ini"

if [ ! -f "${PHP_FPM_BINARY}" ]; then
    echo -e "${RED}ERROR: PHP FPM binary not found at ${PHP_FPM_BINARY}${NC}"
    exit 1
fi

if [ ! -f "${FPM_CONF}" ]; then
    echo -e "${RED}ERROR: PHP-FPM config not found at ${FPM_CONF}${NC}"
    exit 1
fi

PHP_INI_OPT=""
if [ -f "${PHP_INI}" ]; then
    PHP_INI_OPT="-c ${PHP_INI}"
    echo -e "${GREEN}Using php.ini: ${PHP_INI}${NC}"
fi

echo -e "${GREEN}Starting PHP-FPM...${NC}"
echo "Binary: ${PHP_FPM_BINARY}"
echo "Config: ${FPM_CONF}"

# Run PHP-FPM
# -y: path to fpm conf
# -c: path to php.ini (if provided)
# -R: allow running as root (needed in Docker if running as root)
"${PHP_FPM_BINARY}" -y "${FPM_CONF}" ${PHP_INI_OPT} -R

echo -e "${GREEN}✓ PHP-FPM started successfully (background)${NC}"

