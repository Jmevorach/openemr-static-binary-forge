#!/usr/bin/env bash
# Script to build and run OpenEMR Apache PHP-FPM in a Docker container (Linux amd64)

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LINUX_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
PROJECT_ROOT="$( cd "${LINUX_DIR}/.." && pwd )"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Running OpenEMR with Apache PHP-FPM in Docker (Linux amd64)${NC}"
echo -e "${GREEN}============================================================================${NC}"

# Check for binaries
PHP_FPM=$(find "${LINUX_DIR}" -maxdepth 1 -type f -name "php-fpm-*-linux-amd64" | head -1)
PHP_CLI=$(find "${LINUX_DIR}" -maxdepth 1 -type f -name "php-cli-*-linux-amd64" | head -1)
PHAR=$(find "${LINUX_DIR}" -maxdepth 1 -type f -name "openemr-*.phar" | head -1)

if [[ -z "${PHP_FPM}" ]] || [[ -z "${PHP_CLI}" ]] || [[ -z "${PHAR}" ]]; then
    echo -e "${RED}ERROR: Required binaries or PHAR not found in ${LINUX_DIR}${NC}"
    echo "Please run the build script first:"
    echo "  cd ${LINUX_DIR} && ./build-linux.sh"
    exit 1
fi

echo -e "${GREEN}✓ Found required components${NC}"
echo "PHP FPM: $(basename "${PHP_FPM}")"
echo "PHP CLI: $(basename "${PHP_CLI}")"
echo "PHAR:    $(basename "${PHAR}")"
echo ""

# Build the Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t openemr-apache-fpm-amd64 \
    -f "${SCRIPT_DIR}/Dockerfile.docker" \
    "${LINUX_DIR}"

echo ""
echo -e "${GREEN}✓ Image built successfully${NC}"
echo -e "${YELLOW}Starting container on http://localhost:8081...${NC}"

# Remove existing container if it exists
docker rm -f openemr-apache-fpm >/dev/null 2>&1 || true

# Run the container
# We map port 8081 in the container to 8081 on the host to avoid conflict with CGI test
docker run --rm \
    -p 8081:8080 \
    --name openemr-apache-fpm \
    openemr-apache-fpm-amd64

