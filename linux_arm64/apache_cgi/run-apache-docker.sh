#!/usr/bin/env bash
# Script to build and run OpenEMR Apache CGI in a Docker container (Linux arm64)

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
echo -e "${GREEN}Running OpenEMR with Apache CGI in Docker (Linux arm64)${NC}"
echo -e "${GREEN}============================================================================${NC}"

# Check for binaries
PHP_CGI=$(find "${LINUX_DIR}" -maxdepth 1 -type f -name "php-cgi-*-linux-arm64" | head -1)
PHP_CLI=$(find "${LINUX_DIR}" -maxdepth 1 -type f -name "php-cli-*-linux-arm64" | head -1)
PHAR=$(find "${LINUX_DIR}" -maxdepth 1 -type f -name "openemr-*.phar" | head -1)

if [[ -z "${PHP_CGI}" ]] || [[ -z "${PHP_CLI}" ]] || [[ -z "${PHAR}" ]]; then
    echo -e "${RED}ERROR: Required binaries or PHAR not found in ${LINUX_DIR}${NC}"
    echo "Please run the build script first:"
    echo "  cd ${LINUX_DIR} && ./build-linux.sh"
    exit 1
fi

echo -e "${GREEN}✓ Found required components${NC}"
echo "PHP CGI: $(basename "${PHP_CGI}")"
echo "PHP CLI: $(basename "${PHP_CLI}")"
echo "PHAR:    $(basename "${PHAR}")"
echo ""

# Build the Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t openemr-apache-cgi-arm64 \
    -f "${SCRIPT_DIR}/Dockerfile.docker" \
    "${LINUX_DIR}"

echo ""
echo -e "${GREEN}✓ Image built successfully${NC}"
echo -e "${YELLOW}Starting container on http://localhost:8080...${NC}"

# Remove existing container if it exists
docker rm -f openemr-apache-cgi >/dev/null 2>&1 || true

# Run the container
# We map port 8080 in the container to 8080 on the host
docker run --rm \
    -p 8080:8080 \
    --name openemr-apache-cgi \
    openemr-apache-cgi-arm64

