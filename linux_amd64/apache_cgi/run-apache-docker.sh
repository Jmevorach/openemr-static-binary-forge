#!/usr/bin/env bash
# Script to build and run OpenEMR Apache CGI in a Docker container (Linux amd64)

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
echo -e "${GREEN}Running OpenEMR with Apache CGI in Docker (Linux amd64)${NC}"
echo -e "${GREEN}============================================================================${NC}"

# Check for binaries
PHP_CGI=$(find "${LINUX_DIR}" -maxdepth 1 -type f -name "php-cgi-*-linux-amd64" | head -1)
PHP_CLI=$(find "${LINUX_DIR}" -maxdepth 1 -type f -name "php-cli-*-linux-amd64" | head -1)
PHAR=$(find "${LINUX_DIR}" -maxdepth 1 -type f -name "openemr-*.phar" | head -1)

if [ -z "${PHP_CGI}" ] || [ -z "${PHP_CLI}" ] || [ -z "${PHAR}" ]; then
    echo -e "${RED}ERROR: Required components not found in ${LINUX_DIR}${NC}"
    echo "Please run the build script first:"
    echo "  cd ${LINUX_DIR} && ./build-linux.sh"
    exit 1
fi

echo -e "✓ Found required components"
echo -e "PHP CGI: $(basename "${PHP_CGI}")"
echo -e "PHP CLI: $(basename "${PHP_CLI}")"
echo -e "PHAR:    $(basename "${PHAR}")"
echo ""

# Build the Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build --platform linux/amd64 -t openemr-apache-cgi-amd64 -f "${SCRIPT_DIR}/Dockerfile.docker" "${LINUX_DIR}"

# Run the container
echo -e "${YELLOW}Starting container on http://localhost:8080...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop.${NC}"

# Remove existing container if it exists
docker rm -f openemr-apache-amd64 >/dev/null 2>&1 || true

# Check if port 8080 is already in use
if lsof -i :8080 >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Port 8080 is already in use.${NC}"
    echo "Please stop the other process or modify this script to use a different port."
    exit 1
fi

docker run --rm --platform linux/amd64 -p 8080:8080 --name openemr-apache-amd64 openemr-apache-cgi-amd64

