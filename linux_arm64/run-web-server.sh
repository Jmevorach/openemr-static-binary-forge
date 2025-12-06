#!/usr/bin/env bash
# ==============================================================================
# OpenEMR Web Server Launcher (Linux arm64) using Docker Compose
# ==============================================================================
# This script builds a Docker image for the OpenEMR static binary and runs it
# using Docker Compose.
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
echo -e "${GREEN}OpenEMR Web Server Launcher (Linux arm64) - Docker Mode${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""

# Check for Docker and Docker Compose
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker is not installed or not in PATH.${NC}"
    echo "Please install Docker Desktop (macOS/Windows) or Docker Engine (Linux)."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker daemon is not running.${NC}"
    echo "Please start Docker Desktop or the Docker daemon."
    exit 1
fi

if ! command -v docker compose >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker Compose is not installed or not in PATH.${NC}"
    echo "Please install Docker Compose (usually comes with Docker Desktop)."
    exit 1
fi

echo -e "${GREEN}✓ Docker and Docker Compose are installed and running${NC}"
echo ""

# Find the binary
BINARY_PATTERN="openemr-*-linux-arm64"
BINARY=$(find "${SCRIPT_DIR}" -maxdepth 1 -type f -name "${BINARY_PATTERN}" -perm +111 2>/dev/null | head -1)

if [ -z "${BINARY}" ] || [ ! -f "${BINARY}" ]; then
    echo -e "${RED}ERROR: Could not find OpenEMR binary${NC}"
    echo "Expected: ${SCRIPT_DIR}/${BINARY_PATTERN}"
    echo ""
    echo "Please build the binary first using: ./build-linux.sh"
    exit 1
fi

echo -e "${GREEN}Found binary: $(basename "${BINARY}")${NC}"
echo ""

# Find the standalone PHP CLI binary
PHP_CLI_PATTERN="php-cli-*-linux-arm64"
PHP_CLI_BINARY=$(find "${SCRIPT_DIR}" "${PROJECT_ROOT}" -maxdepth 1 -type f -name "${PHP_CLI_PATTERN}" -perm +111 2>/dev/null | head -1)

if [ -z "${PHP_CLI_BINARY}" ] || [ ! -f "${PHP_CLI_BINARY}" ]; then
    echo -e "${RED}ERROR: PHP CLI binary not found${NC}"
    echo ""
    echo "The PHP CLI binary is required for PHAR extraction with proper memory limits."
    echo "Expected in: ${SCRIPT_DIR}/php-cli-*-linux-arm64 or ${PROJECT_ROOT}/php-cli-*-linux-arm64"
    echo ""
    echo "Please rebuild using: ./build-linux.sh"
    exit 1
fi

echo -e "${GREEN}Found PHP CLI binary: $(basename "${PHP_CLI_BINARY}")${NC}"
echo ""

# Find the PHAR file
PHAR_PATTERN="openemr-*.phar"
PHAR_FILE=$(find "${SCRIPT_DIR}" "${PROJECT_ROOT}" -maxdepth 1 -type f -name "${PHAR_PATTERN}" 2>/dev/null | head -1)

if [ -z "${PHAR_FILE}" ] || [ ! -f "${PHAR_FILE}" ]; then
    echo -e "${YELLOW}PHAR file not found in ${SCRIPT_DIR} or ${PROJECT_ROOT}${NC}"
    echo ""
    echo "The PHAR file should have been saved during the build process."
    echo "Please rebuild to save the PHAR file:"
    echo "  cd ${SCRIPT_DIR}"
    echo "  ./build-linux.sh"
    exit 1
fi

echo -e "${GREEN}Found PHAR file: $(basename "${PHAR_FILE}")${NC}"
echo ""

# Build the Docker image
echo "Building Docker image for OpenEMR static binary..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yml" build || {
    echo -e "${RED}ERROR: Docker image build failed${NC}"
    exit 1
}
echo -e "${GREEN}✓ Docker image built successfully${NC}"
echo ""

echo "Starting OpenEMR with Docker Compose..."
echo ""
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
echo "  docker compose -f ${SCRIPT_DIR}/docker-compose.yml logs -f"
echo ""
echo "To stop:"
echo "  docker compose -f ${SCRIPT_DIR}/docker-compose.yml down"
echo ""

# Start the Docker Compose services in foreground to stream logs
OPENEMR_PORT="${PORT}" docker compose -f "${SCRIPT_DIR}/docker-compose.yml" up --remove-orphans
