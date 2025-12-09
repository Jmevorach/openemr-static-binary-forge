#!/usr/bin/env bash
# ==============================================================================
# Build OpenEMR Static Binary for Linux (arm64) using Docker
# ==============================================================================
# This script builds a self-contained OpenEMR binary for Linux arm64 using
# Static PHP CLI (SPC) inside a Docker container.
# Based on the method described at: https://www.bosunegberinde.com/articles/building-php-binary
#
# Usage:
#   ./build-linux.sh [openemr_version]
#
# Environment Variables:
#   PHP_VERSION - PHP major.minor version to use (default: 8.5)
#                 Example: PHP_VERSION=8.4 ./build-linux.sh
#
# Example:
#   ./build-linux.sh v7_0_3_4
#   PHP_VERSION=8.4 ./build-linux.sh v7_0_3_4
#
# Requirements:
#   - Docker installed and running
#   - Internet connection for downloading dependencies during build
#
# The resulting binary will be in the linux_arm64/ directory.
# ==============================================================================

# ==============================================================================
# Version Configuration
# ==============================================================================
# All package versions are defined here as environment variables for easy
# maintenance and stability. Override these variables before running the script
# to use different versions.
#
# OpenEMR Configuration:
export OPENEMR_VERSION="${OPENEMR_VERSION:-v7_0_3_4}"
#
# Docker Base Image:
export DOCKER_BASE_IMAGE="${DOCKER_BASE_IMAGE:-ubuntu:24.04}"
#
# PHP Configuration:
export PHP_VERSION="${PHP_VERSION:-8.5}"
#
# Static PHP CLI (SPC) Configuration:
# The static-php-cli repository is cloned from GitHub. Pinned to a specific commit
# for stability. Override STATIC_PHP_CLI_COMMIT to use a different commit.
export STATIC_PHP_CLI_REPO="${STATIC_PHP_CLI_REPO:-https://github.com/crazywhalecc/static-php-cli.git}"
export STATIC_PHP_CLI_BRANCH="${STATIC_PHP_CLI_BRANCH:-main}"
export STATIC_PHP_CLI_COMMIT="${STATIC_PHP_CLI_COMMIT:-59a6e2753265622b7e8d599f791f1ad3c2e60388}"
#
# PHP Extensions (comma-separated list):
export PHP_EXTENSIONS="${PHP_EXTENSIONS:-bcmath,exif,gd,intl,ldap,mbstring,mysqli,opcache,openssl,pcntl,pdo_mysql,phar,redis,soap,sockets,zip,imagick}"
# ==============================================================================

set -euo pipefail

# Ensure output is unbuffered for streaming to terminal
export PYTHONUNBUFFERED=1
export PHP_BIN_STREAM=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Handle arguments - support --debug flag
DEBUG_MODE=false
OPENEMR_TAG=""
for arg in "$@"; do
    if [[ "${arg}" == "--debug" ]]; then
        DEBUG_MODE=true
    elif [[ -z "${OPENEMR_TAG}" ]]; then
        OPENEMR_TAG="${arg}"
    fi
done
# Use version variables (allow command-line overrides, fallback to exported defaults)
OPENEMR_TAG="${OPENEMR_TAG:-${OPENEMR_VERSION}}"
PHP_VERSION="${PHP_VERSION:-${PHP_VERSION}}"

if [[ "${DEBUG_MODE}" == "true" ]]; then
    echo -e "${YELLOW}[DEBUG MODE ENABLED]${NC}"
fi

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Building OpenEMR Static Binary for Linux (arm64) using Docker${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""

echo "OpenEMR Version: ${OPENEMR_TAG}"
echo "PHP Version: ${PHP_VERSION}"
echo "Project Root: ${PROJECT_ROOT}"
echo "Build Directory: ${SCRIPT_DIR}"
echo ""

# Check if Docker is installed and running
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker is not installed${NC}"
    echo ""
    echo "Please install Docker:"
    echo "  macOS: https://docs.docker.com/desktop/install/mac-install/"
    echo "  Linux: https://docs.docker.com/engine/install/"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker is not running${NC}"
    echo ""
    echo "Please start Docker Desktop or the Docker daemon"
    exit 1
fi

echo -e "${GREEN}✓ Docker is installed and running${NC}"
echo ""

# Docker image to use for building
DOCKER_IMAGE="${DOCKER_BASE_IMAGE}"
ARCH="aarch64"
TARGET_ARCH="arm64"

echo "Using Docker image: ${DOCKER_IMAGE}"
echo "Target architecture: ${TARGET_ARCH}"
echo ""

# Create a Dockerfile for the build environment
DOCKERFILE="${SCRIPT_DIR}/Dockerfile.build"
cat > "${DOCKERFILE}" << DOCKERFILE_EOF
ARG DOCKER_BASE_IMAGE=${DOCKER_BASE_IMAGE}
FROM \${DOCKER_BASE_IMAGE}

# Accept PHP version as build argument
ARG PHP_VERSION_MAJOR_MINOR=${PHP_VERSION}
ARG PHP_VERSION_FULL

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \\
    build-essential \\
    git \\
    curl \\
    wget \\
    ca-certificates \\
    libpng-dev \\
    libjpeg-dev \\
    libfreetype6-dev \\
    libxml2-dev \\
    libzip-dev \\
    libmagickwand-dev \\
    pkg-config \\
    composer \\
    nodejs \\
    npm \\
    bison \\
    re2c \\
    flex \\
    autopoint \\
    cmake \\
    patchelf \\
    sudo \\
    libssl-dev \\
    libcurl4-openssl-dev \\
    libonig-dev \\
    libsqlite3-dev \\
    libicu-dev \\
    && rm -rf /var/lib/apt/lists/*

# Build PHP from source (official php.net source)
# Get latest PHP version from official releases if not provided
RUN cd /tmp && \\
    if [ -z "\${PHP_VERSION_FULL}" ]; then \\
        echo "Fetching latest PHP \${PHP_VERSION_MAJOR_MINOR} version..." && \\
        PHP_VERSION_FULL=\$(curl -s "https://www.php.net/releases/index.php?json&version=\${PHP_VERSION_MAJOR_MINOR}" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4) && \\
        if [ -z "\${PHP_VERSION_FULL}" ]; then \\
            echo "ERROR: Could not determine PHP version. Using \${PHP_VERSION_MAJOR_MINOR}.0 as fallback" && \\
            PHP_VERSION_FULL="\${PHP_VERSION_MAJOR_MINOR}.0"; \\
        fi; \\
    else \\
        PHP_VERSION_FULL="\${PHP_VERSION_FULL}"; \\
    fi && \\
    PHP_INSTALL_DIR="/usr/local/php\${PHP_VERSION_MAJOR_MINOR}" && \\
    echo "Building PHP \${PHP_VERSION_FULL} from official php.net source..." && \\
    curl -L -o php-\${PHP_VERSION_FULL}.tar.gz "https://www.php.net/distributions/php-\${PHP_VERSION_FULL}.tar.gz" && \\
    tar -xzf php-\${PHP_VERSION_FULL}.tar.gz && \\
    cd php-\${PHP_VERSION_FULL} && \\
    ./configure \\
        --prefix=\${PHP_INSTALL_DIR} \\
        --with-config-file-path=\${PHP_INSTALL_DIR}/etc \\
        --enable-cli \\
        --disable-cgi \\
        --with-curl \\
        --with-openssl \\
        --with-zlib \\
        --with-zip \\
        --enable-mbstring \\
        --with-onig \\
        --enable-xml \\
        --enable-dom \\
        --enable-intl \\
        --enable-phar \\
        --enable-opcache \\
        --without-pear && \\
    make -j\$(nproc) && \\
    make install && \\
    mkdir -p \${PHP_INSTALL_DIR}/etc && \\
    ln -sf \${PHP_INSTALL_DIR}/bin/php /usr/local/bin/php && \\
    ln -sf \${PHP_INSTALL_DIR}/bin/php /usr/bin/php && \\
    cp php.ini-production \${PHP_INSTALL_DIR}/etc/php.ini && \\
    cd / && \\
    rm -rf /tmp/php-\${PHP_VERSION_FULL}* && \\
    php -v && \\
    echo "PHP \${PHP_VERSION_FULL} built and installed successfully"

WORKDIR /build
DOCKERFILE_EOF

echo "Building Docker image for Linux arm64 build..."
echo "Using PHP version: ${PHP_VERSION}"
echo "Using base image: ${DOCKER_BASE_IMAGE}"
docker build --platform linux/arm64 \
    --build-arg DOCKER_BASE_IMAGE="${DOCKER_BASE_IMAGE}" \
    --build-arg PHP_VERSION_MAJOR_MINOR="${PHP_VERSION}" \
    -t openemr-builder-arm64:latest \
    -f "${DOCKERFILE}" \
    "${SCRIPT_DIR}" || {
    echo -e "${RED}ERROR: Failed to build Docker image${NC}"
    exit 1
}

echo -e "${GREEN}✓ Docker image built${NC}"
echo ""

# Create build script that will run inside Docker
BUILD_SCRIPT="${SCRIPT_DIR}/docker-build-internal.sh"
cat > "${BUILD_SCRIPT}" << 'BUILD_SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

OPENEMR_TAG="${1:-v7_0_3_4}"
PHP_VERSION="${2:-8.5}"
STATIC_PHP_CLI_REPO="${3:-https://github.com/crazywhalecc/static-php-cli.git}"
STATIC_PHP_CLI_BRANCH="${4:-main}"
STATIC_PHP_CLI_COMMIT="${5:-}"
PHP_EXTENSIONS="${6:-bcmath,exif,gd,intl,ldap,mbstring,mysqli,opcache,openssl,pcntl,pdo_mysql,phar,redis,soap,sockets,zip,imagick}"
ARCH="aarch64"
TARGET_ARCH="arm64"

cd /build

# Detect system resources
CPU_CORES=$(nproc)
PHYSICAL_CORES=${CPU_CORES}
TOTAL_RAM_GB=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))

PARALLEL_JOBS=$((PHYSICAL_CORES + 1))
if [ "${PARALLEL_JOBS}" -gt "${CPU_CORES}" ]; then
    PARALLEL_JOBS="${CPU_CORES}"
fi
if [ "${PARALLEL_JOBS}" -lt 2 ]; then
    PARALLEL_JOBS=2
fi

COMPOSER_MEMORY_LIMIT=$((TOTAL_RAM_GB / 2))
if [ "${COMPOSER_MEMORY_LIMIT}" -gt 4 ]; then
    COMPOSER_MEMORY_LIMIT=4
fi
if [ "${COMPOSER_MEMORY_LIMIT}" -lt 1 ]; then
    COMPOSER_MEMORY_LIMIT=1
fi
export COMPOSER_MEMORY_LIMIT="${COMPOSER_MEMORY_LIMIT}G"

echo "System resources:"
echo "  CPU cores: ${CPU_CORES}"
echo "  RAM: ${TOTAL_RAM_GB} GB"
echo "  Parallel jobs: ${PARALLEL_JOBS}"
echo "  Composer memory: ${COMPOSER_MEMORY_LIMIT}"
echo ""

# Step 1: Prepare OpenEMR
echo "Step 1/5: Preparing OpenEMR application..."
OPENEMR_DIR="/build/openemr-source"
PHAR_FILE="/build/openemr.phar"

# Clean up any leftover files from previous builds
echo "Cleaning up any previous build artifacts..."
rm -rf /build/openemr-source /build/openemr-phar /build/openemr.phar 2>/dev/null || true

echo "Cloning OpenEMR ${OPENEMR_TAG}..."
MAX_RETRIES=3
RETRY_COUNT=0
while [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; do
    if git clone --depth 1 --branch "${OPENEMR_TAG}" https://github.com/openemr/openemr.git openemr-source; then
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; then
        echo "Clone attempt ${RETRY_COUNT} failed. Retrying in 5 seconds..."
        sleep 5
        rm -rf openemr-source 2>/dev/null || true
    else
        echo "ERROR: Failed to clone OpenEMR after ${MAX_RETRIES} attempts"
        exit 1
    fi
done

cd openemr-source
mkdir -p /build/openemr-phar
git archive HEAD | tar -x -C /build/openemr-phar
cd /build/openemr-phar

rm -rf .git tests/ .github/ docs/ 2>/dev/null || true

echo "Installing production dependencies..."
if [ -f "composer.json" ] && command -v composer >/dev/null 2>&1; then
    COMPOSER_MEMORY_LIMIT="${COMPOSER_MEMORY_LIMIT}" \
    COMPOSER_PROCESS_TIMEOUT=0 \
    composer install \
        --ignore-platform-reqs \
        --no-dev \
        --optimize-autoloader \
        --prefer-dist \
        --no-interaction \
        2>&1 | grep -v "^#" || true
fi

# Build frontend assets if needed
if [ -f "package.json" ] && command -v npm >/dev/null 2>&1; then
    echo "Building frontend assets..."
    
    # Make npm fully non-interactive
    export npm_config_yes=true
    export npm_config_loglevel=warn
    export CI=true
    
    # Install global dependencies needed by OpenEMR's postinstall scripts
    echo "Installing global npm dependencies (napa, gulp-cli)..."
    npm install -g --yes napa gulp-cli 2>&1 || {
        echo "WARNING: Failed to install global npm deps"
        echo "Continuing anyway..."
    }
    
    # Install npm dependencies (WITHOUT --production flag to get devDependencies needed for building)
    echo "Installing npm dependencies (including devDependencies for build tools)..."
    NODE_OPTIONS="--max-old-space-size=$((TOTAL_RAM_GB * 512))" npm ci 2>&1 || {
        echo "WARNING: npm ci had issues, trying npm install as fallback..."
        NODE_OPTIONS="--max-old-space-size=$((TOTAL_RAM_GB * 512))" npm install 2>&1 || {
            echo "WARNING: npm install also had issues, but continuing..."
        }
    }
    
    # Run build command to compile CSS/JS assets
    # OpenEMR uses Gulp via npm run build to compile CSS and JavaScript
    echo "Building frontend assets with npm run build (runs Gulp)..."
    BUILD_SUCCESS=false
    
    # OpenEMR uses 'npm run build' which triggers Gulp to compile assets
    if npm run | grep -q "^  build" || grep -q '"build"' package.json 2>/dev/null; then
        echo "Running npm run build to compile CSS and JavaScript assets..."
        NODE_OPTIONS="--max-old-space-size=$((TOTAL_RAM_GB * 512))" npm run build 2>&1 && {
            BUILD_SUCCESS=true
            echo "✓ Frontend assets built successfully (CSS and JavaScript compiled)"
        } || {
            echo "WARNING: npm run build had issues"
        }
    else
        # Fallback: try gulp directly if npm run build doesn't exist
        if command -v gulp >/dev/null 2>&1 && ([ -f "gulpfile.js" ] || [ -f "Gulpfile.js" ]); then
            echo "Running gulp directly to build frontend assets..."
            NODE_OPTIONS="--max-old-space-size=$((TOTAL_RAM_GB * 512))" gulp 2>&1 && {
                BUILD_SUCCESS=true
                echo "✓ Gulp build completed successfully"
            } || {
                echo "WARNING: gulp build had issues"
            }
        fi
    fi
    
    if [ "${BUILD_SUCCESS}" != "true" ]; then
        echo "ERROR: Frontend build failed!"
        echo "CSS and JavaScript assets were NOT compiled."
        echo "OpenEMR will not have working styles or JavaScript."
        echo ""
        echo "This is a critical issue. Please check:"
        echo "  - Node.js and npm are properly installed"
        echo "  - All npm dependencies installed correctly"
        echo "  - gulp-cli is installed globally"
        exit 1
    fi
    
    echo "Frontend build step completed successfully."
fi

echo "Creating PHAR archive..."
cat > /build/create-phar.php << 'PHARBUILDER'
<?php
ini_set('phar.readonly', '0');
$pharFile = $argv[1];
$sourceDir = $argv[2];
if (file_exists($pharFile)) {
    unlink($pharFile);
}
$phar = new Phar($pharFile);
$phar->buildFromDirectory($sourceDir);
$phar->setStub($phar->createDefaultStub('interface/main/main.php'));
$phar->compressFiles(Phar::GZ);
echo "PHAR created: $pharFile\n";
PHARBUILDER

php -d phar.readonly=0 /build/create-phar.php "${PHAR_FILE}" /build/openemr-phar

if [ ! -f "${PHAR_FILE}" ]; then
    echo "ERROR: Failed to create PHAR file"
    exit 1
fi

echo "✓ PHAR created"
echo ""

# Step 2: Build Static PHP CLI from source
echo "Step 2/5: Building Static PHP CLI (SPC) from source..."
# Build in /tmp to avoid Docker volume mount issues
SPC_BUILD_DIR="/tmp/spc-build"
SPC_BIN="/tmp/spc-build/spc"

# Clean up any previous build
rm -rf "${SPC_BUILD_DIR}" 2>/dev/null || true
mkdir -p "${SPC_BUILD_DIR}"

echo "Cloning static-php-cli repository..."
cd /tmp
if [ -d "static-php-cli" ]; then
    rm -rf static-php-cli
fi

MAX_CLONE_ATTEMPTS=3
CLONE_ATTEMPT=0
CLONE_SUCCESS=false

while [ ${CLONE_ATTEMPT} -lt ${MAX_CLONE_ATTEMPTS} ] && [ "${CLONE_SUCCESS}" != "true" ]; do
    CLONE_ATTEMPT=$((CLONE_ATTEMPT + 1))
    echo "Clone attempt ${CLONE_ATTEMPT}/${MAX_CLONE_ATTEMPTS}..."
    
    # Determine clone command based on whether commit or branch is specified
    if [ -n "${STATIC_PHP_CLI_COMMIT}" ]; then
        if git clone --depth 1 "${STATIC_PHP_CLI_REPO}" "${SPC_BUILD_DIR}"; then
            cd "${SPC_BUILD_DIR}" && git checkout "${STATIC_PHP_CLI_COMMIT}" && cd /tmp
            CLONE_SUCCESS=true
        fi
    elif [ -n "${STATIC_PHP_CLI_BRANCH}" ]; then
        if git clone --depth 1 --branch "${STATIC_PHP_CLI_BRANCH}" "${STATIC_PHP_CLI_REPO}" "${SPC_BUILD_DIR}"; then
            CLONE_SUCCESS=true
        fi
    else
        if git clone --depth 1 "${STATIC_PHP_CLI_REPO}" "${SPC_BUILD_DIR}"; then
            CLONE_SUCCESS=true
        fi
    fi
    
    if [ "${CLONE_SUCCESS}" = "true" ]; then
        break
    else
        echo "Clone failed, retrying..."
        rm -rf "${SPC_BUILD_DIR}" 2>/dev/null || true
        if [ ${CLONE_ATTEMPT} -lt ${MAX_CLONE_ATTEMPTS} ]; then
            sleep $((CLONE_ATTEMPT * 2))
        fi
    fi
done

if [ "${CLONE_SUCCESS}" != "true" ]; then
    echo "ERROR: Failed to clone static-php-cli repository after ${MAX_CLONE_ATTEMPTS} attempts"
    exit 1
fi

cd "${SPC_BUILD_DIR}"

echo "Installing Composer dependencies..."
if ! command -v composer >/dev/null 2>&1; then
    echo "ERROR: Composer is not installed"
    exit 1
fi

# Install dependencies
if ! composer install --no-interaction --prefer-dist --optimize-autoloader; then
    echo "ERROR: Failed to install Composer dependencies"
    exit 1
fi

echo "Building SPC PHAR..."
# Build the PHAR using box (installed via composer)
if [ -f "vendor/bin/box" ]; then
    BOX_BIN="vendor/bin/box"
elif [ -f "box" ]; then
    BOX_BIN="./box"
else
    echo "ERROR: Could not find box binary"
    exit 1
fi

# Build the PHAR
if ! php "${BOX_BIN}" compile --no-interaction; then
    echo "ERROR: Failed to build SPC PHAR"
    exit 1
fi

# Find the built binary (Box creates spc.phar)
if [ -f "${SPC_BUILD_DIR}/spc.phar" ]; then
    SPC_BIN="${SPC_BUILD_DIR}/spc.phar"
    # Rename to spc for convenience
    mv "${SPC_BIN}" "${SPC_BUILD_DIR}/spc" 2>/dev/null || true
    SPC_BIN="${SPC_BUILD_DIR}/spc"
elif [ -f "${SPC_BUILD_DIR}/spc" ]; then
    SPC_BIN="${SPC_BUILD_DIR}/spc"
elif [ -f "${SPC_BUILD_DIR}/build/spc" ]; then
    SPC_BIN="${SPC_BUILD_DIR}/build/spc"
else
    echo "ERROR: Could not find built SPC binary"
    echo "Looking in: ${SPC_BUILD_DIR}"
    find "${SPC_BUILD_DIR}" -name "spc*" -type f 2>/dev/null | head -5 || true
    exit 1
fi

# Make it executable
chmod +x "${SPC_BIN}"

# Verify the binary works
echo "Verifying built SPC binary..."
if ! "${SPC_BIN}" --version >/dev/null 2>&1; then
    echo "ERROR: Built SPC binary version check failed"
    exit 1
fi

# Test PHAR loading
if ! "${SPC_BIN}" doctor --version >/dev/null 2>&1; then
    echo "ERROR: Built SPC binary PHAR loading test failed"
    "${SPC_BIN}" doctor --version 2>&1 | head -5 || true
    exit 1
fi

echo "✓ Static PHP CLI built from source successfully"
echo ""

# Step 3: Download dependencies
echo "Step 3/5: Downloading dependencies..."
# PHP_EXTENSIONS is passed as parameter

# Run SPC commands from /tmp to avoid volume mount issues
cd /tmp
"${SPC_BIN}" doctor --auto-fix || true

echo "Downloading PHP and extension sources..."
MAX_DOWNLOAD_RETRIES=3
DOWNLOAD_RETRY_COUNT=0

while [ ${DOWNLOAD_RETRY_COUNT} -lt ${MAX_DOWNLOAD_RETRIES} ]; do
    if "${SPC_BIN}" download \
        --with-php="${PHP_VERSION}" \
        --for-extensions="${PHP_EXTENSIONS}" \
        --retry 5; then
        break
    fi
    
    DOWNLOAD_RETRY_COUNT=$((DOWNLOAD_RETRY_COUNT + 1))
    if [ ${DOWNLOAD_RETRY_COUNT} -lt ${MAX_DOWNLOAD_RETRIES} ]; then
        WAIT_TIME=$((DOWNLOAD_RETRY_COUNT * 30))
        echo "Download failed (attempt ${DOWNLOAD_RETRY_COUNT}/${MAX_DOWNLOAD_RETRIES})."
        echo "Waiting ${WAIT_TIME} seconds before retrying..."
        sleep ${WAIT_TIME}
    else
        echo "ERROR: Failed to download dependencies after ${MAX_DOWNLOAD_RETRIES} attempts"
        exit 1
    fi
done

echo "✓ Dependencies downloaded"
echo ""

# Step 4: Build static PHP
echo "Step 4/5: Building static PHP binaries..."
export MAKEFLAGS="-j${PARALLEL_JOBS}"
export MAKE_JOBS="${PARALLEL_JOBS}"
export NPROC="${PARALLEL_JOBS}"

# Run build from /tmp to avoid volume mount issues
# Note: PHP version is set during download step, not build step
cd /tmp
# Add --debug flag for more verbose output to help diagnose issues
"${SPC_BIN}" build \
    --build-cli \
    --build-micro \
    --debug \
    "${PHP_EXTENSIONS}"

echo "✓ Static PHP binaries built"
echo ""

# Step 5: Combine PHAR with MicroSFX
echo "Step 5/5: Combining PHAR with MicroSFX..."
# SPC build creates files in current directory or buildroot, search both /tmp and /build
MICRO_SFX=$(find /tmp /build -name "micro.sfx" -type f 2>/dev/null | head -1)

if [ -z "${MICRO_SFX}" ] || [ ! -f "${MICRO_SFX}" ]; then
    echo "ERROR: Could not find micro.sfx file"
    exit 1
fi

FINAL_BINARY_NAME="openemr-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
FINAL_BINARY="/output/${FINAL_BINARY_NAME}"

# Increase PHP memory limit for combining large PHAR files
# Run from /tmp to avoid volume mount issues
cd /tmp
export PHP_MEMORY_LIMIT=4096M
php -d memory_limit=4096M "${SPC_BIN}" micro:combine "${PHAR_FILE}" -O "${FINAL_BINARY}"

if [ -f "${FINAL_BINARY}" ]; then
    chmod +x "${FINAL_BINARY}"
    echo "✓ Binary created: ${FINAL_BINARY_NAME}"
else
    echo "ERROR: Failed to create final binary"
    exit 1
fi

# Copy PHP CLI and PHAR
# SPC build creates buildroot in current directory, search both /tmp and /build
PHP_CLI_BINARY=$(find /tmp /build -name "php" -type f -path "*/buildroot/bin/php" 2>/dev/null | head -1)
if [ -n "${PHP_CLI_BINARY}" ] && [ -f "${PHP_CLI_BINARY}" ]; then
    cp "${PHP_CLI_BINARY}" "/output/php-cli-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    chmod +x "/output/php-cli-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    echo "✓ PHP CLI binary saved"
fi

if [ -f "${PHAR_FILE}" ]; then
    cp "${PHAR_FILE}" "/output/openemr-${OPENEMR_TAG}.phar"
    echo "✓ PHAR archive saved"
fi

echo ""
echo "Build complete!"
BUILD_SCRIPT_EOF

chmod +x "${BUILD_SCRIPT}"

# Create output directory
OUTPUT_DIR="${SCRIPT_DIR}/output"
mkdir -p "${OUTPUT_DIR}"

echo "Starting Docker build container..."
echo "This may take 30-60 minutes depending on your system."
echo ""

# Run the build inside Docker
# Allocate 16GB RAM for faster builds (adjust based on your Docker Desktop settings)
CONTAINER_NAME="openemr-builder-arm64-$(date +%s)"
docker run --name "${CONTAINER_NAME}" \
    --platform linux/arm64 \
    --memory=16g \
    --memory-swap=16g \
    -v "${SCRIPT_DIR}:/build" \
    -v "${OUTPUT_DIR}:/output" \
    -w /build \
    openemr-builder-arm64:latest \
    bash /build/docker-build-internal.sh "${OPENEMR_TAG}" "${PHP_VERSION}" "${STATIC_PHP_CLI_REPO}" "${STATIC_PHP_CLI_BRANCH}" "${STATIC_PHP_CLI_COMMIT}" "${PHP_EXTENSIONS}" || {
    echo -e "${RED}ERROR: Docker build failed${NC}"
    echo ""
    echo "Attempting to extract build logs from container..."
    # Try to extract logs from the container before removing it
    if docker cp "${CONTAINER_NAME}:/tmp/log/spc.output.log" "${SCRIPT_DIR}/spc-output.log" 2>/dev/null; then
        echo -e "${GREEN}✓ Extracted SPC output log to: ${SCRIPT_DIR}/spc-output.log${NC}"
    fi
    if docker cp "${CONTAINER_NAME}:/tmp/log/spc.shell.log" "${SCRIPT_DIR}/spc-shell.log" 2>/dev/null; then
        echo -e "${GREEN}✓ Extracted SPC shell log to: ${SCRIPT_DIR}/spc-shell.log${NC}"
    fi
    # Remove container after extracting logs
    docker rm "${CONTAINER_NAME}" 2>/dev/null || true
    echo ""
    echo "For more debugging information, check the extracted log files or run with --debug flag."
    exit 1
}

# Remove container on success
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

# Move output files to script directory
if [ -d "${OUTPUT_DIR}" ]; then
    mv "${OUTPUT_DIR}"/* "${SCRIPT_DIR}"/ 2>/dev/null || true
    rmdir "${OUTPUT_DIR}" 2>/dev/null || true
fi

# Copy binary and PHAR to project root for easier access (like macOS build)
FINAL_BINARY="${SCRIPT_DIR}/openemr-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
PHAR_FILE="${SCRIPT_DIR}/openemr-${OPENEMR_TAG}.phar"

if [ -f "${FINAL_BINARY}" ]; then
    BINARY_ROOT="${PROJECT_ROOT}/openemr-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    cp "${FINAL_BINARY}" "${BINARY_ROOT}"
    chmod +x "${BINARY_ROOT}"
    BINARY_SIZE=$(du -h "${BINARY_ROOT}" | cut -f1)
    echo -e "${GREEN}✓ Binary also saved to project root: $(basename "${BINARY_ROOT}") (${BINARY_SIZE})${NC}"
fi

if [ -f "${PHAR_FILE}" ]; then
    PHAR_ROOT="${PROJECT_ROOT}/openemr-${OPENEMR_TAG}.phar"
    cp "${PHAR_FILE}" "${PHAR_ROOT}"
    echo -e "${GREEN}✓ PHAR archive also saved to project root: $(basename "${PHAR_ROOT}")${NC}"
fi

echo ""
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "Binary location: ${FINAL_BINARY}"
if [ -f "${BINARY_ROOT}" ]; then
    echo "Also available at: ${BINARY_ROOT}"
fi
echo ""
echo "To run OpenEMR web server:"
echo "  ./run-web-server.sh [port]"
echo ""
