#!/usr/bin/env bash
# ==============================================================================
# OpenEMR Web Server Launcher (Linux amd64)
# ==============================================================================
# This script runs OpenEMR using Docker Compose with the static binary.
# It automatically builds a Docker image and starts the service.
#
# Usage:
#   ./run-web-server.sh [port]
#
# Example:
#   ./run-web-server.sh 8080
#
# Default port: 8080
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Default port
PORT="${1:-8080}"

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}OpenEMR Web Server Launcher (Linux amd64)${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""

# Check if Docker is available
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker is not installed${NC}"
    echo "Please install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker Compose is not available${NC}"
    echo "Please install Docker Compose or use Docker Desktop which includes it."
    exit 1
fi

# Check for required files
BINARY_PATTERN="openemr-*-linux-amd64"
PHP_CLI_PATTERN="php-cli-*-linux-amd64"
PHAR_PATTERN="openemr-*.phar"

BINARY=$(find "${SCRIPT_DIR}" -maxdepth 1 -type f -name "${BINARY_PATTERN}" -perm +111 2>/dev/null | head -1)
PHP_CLI_BINARY=$(find "${SCRIPT_DIR}" "${PROJECT_ROOT}" -maxdepth 1 -type f -name "${PHP_CLI_PATTERN}" -perm +111 2>/dev/null | head -1)
PHAR_FILE=$(find "${SCRIPT_DIR}" "${PROJECT_ROOT}" -maxdepth 1 -type f -name "${PHAR_PATTERN}" 2>/dev/null | head -1)

if [ -z "${BINARY}" ] || [ ! -f "${BINARY}" ]; then
    echo -e "${RED}ERROR: Could not find OpenEMR binary${NC}"
    echo "Expected: ${SCRIPT_DIR}/${BINARY_PATTERN}"
    echo ""
    echo "Please build the binary first using: ./build-linux.sh"
    exit 1
fi

if [ -z "${PHP_CLI_BINARY}" ] || [ ! -f "${PHP_CLI_BINARY}" ]; then
    echo -e "${RED}ERROR: Could not find PHP CLI binary${NC}"
    echo "Expected: ${SCRIPT_DIR}/${PHP_CLI_PATTERN}"
    echo ""
    echo "Please rebuild using: ./build-linux.sh"
    exit 1
fi

if [ -z "${PHAR_FILE}" ] || [ ! -f "${PHAR_FILE}" ]; then
    echo -e "${RED}ERROR: Could not find PHAR file${NC}"
    echo "Expected: ${SCRIPT_DIR}/${PHAR_PATTERN}"
    echo ""
    echo "Please rebuild using: ./build-linux.sh"
    exit 1
fi

echo -e "${GREEN}Found required files:${NC}"
echo "  Binary: $(basename "${BINARY}")"
echo "  PHP CLI: $(basename "${PHP_CLI_BINARY}")"
echo "  PHAR: $(basename "${PHAR_FILE}")"
echo ""

# Check if Dockerfile and docker-compose.yml exist
if [ ! -f "${SCRIPT_DIR}/Dockerfile" ]; then
    echo -e "${RED}ERROR: Dockerfile not found${NC}"
    exit 1
fi

if [ ! -f "${SCRIPT_DIR}/docker-compose.yml" ]; then
    echo -e "${RED}ERROR: docker-compose.yml not found${NC}"
    exit 1
fi

# Set port environment variable
export OPENEMR_PORT="${PORT}"

echo -e "${BLUE}Building Docker image...${NC}"
echo ""

# Build Docker image
cd "${SCRIPT_DIR}"
docker build -t openemr-static:latest . || {
    echo -e "${RED}ERROR: Failed to build Docker image${NC}"
    exit 1
}

echo ""
echo -e "${GREEN}✓ Docker image built successfully${NC}"
echo ""

# Start with docker-compose
echo -e "${BLUE}Starting OpenEMR with Docker Compose...${NC}"
echo ""

# Use docker compose (newer) or docker-compose (older)
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}OpenEMR is starting...${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "Server information:"
echo "  URL:         http://localhost:${PORT}"
echo "  Mode:        Docker (containerized)"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
echo ""
echo "To view logs:"
echo "  ${COMPOSE_CMD} -f ${SCRIPT_DIR}/docker-compose.yml logs -f"
echo ""
echo "To stop:"
echo "  ${COMPOSE_CMD} -f ${SCRIPT_DIR}/docker-compose.yml down"
echo ""

# Start services
${COMPOSE_CMD} -f "${SCRIPT_DIR}/docker-compose.yml" up
