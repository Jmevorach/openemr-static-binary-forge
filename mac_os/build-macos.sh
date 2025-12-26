#!/usr/bin/env bash
# ==============================================================================
# Build OpenEMR Static Binary for macOS
# ==============================================================================
# This script builds a self-contained OpenEMR binary for macOS using Static PHP CLI (SPC).
# Based on the method described at: https://www.bosunegberinde.com/articles/building-php-binary
#
# Usage:
#   ./build-macos.sh [openemr_version]
#
# Example:
#   ./build-macos.sh v7_0_4
#
# Requirements:
#   - macOS (Darwin)
#   - Git
#   - System libraries for PHP extensions (libpng, libjpeg, etc.)
#
# The resulting binary will be in the mac_os/ directory.
# ==============================================================================

# ==============================================================================
# Version Configuration
# ==============================================================================
# All package versions are defined here as environment variables for easy
# maintenance and stability. Override these variables before running the script
# to use different versions.
#
# OpenEMR Configuration:
export OPENEMR_VERSION="${OPENEMR_VERSION:-v7_0_4}"
#
# PHP Configuration:
export PHP_VERSION="${PHP_VERSION:-8.5}"
#
# Static PHP CLI (SPC) Configuration:
# The static-php-cli is downloaded as a pre-built release from GitHub.
# Pinned to release 2.7.9 for stability. Override to use a different release.
export STATIC_PHP_CLI_RELEASE_TAG="${STATIC_PHP_CLI_RELEASE_TAG:-2.7.9}"
export STATIC_PHP_CLI_REPO="${STATIC_PHP_CLI_REPO:-crazywhalecc/static-php-cli}"
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

if [[ "${DEBUG_MODE}" == "true" ]]; then
    echo -e "${YELLOW}[DEBUG MODE ENABLED]${NC}"
fi

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Building OpenEMR Static Binary for macOS${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""

echo "OpenEMR Version: ${OPENEMR_TAG}"
echo "Project Root: ${PROJECT_ROOT}"
echo "Static Directory: ${SCRIPT_DIR}"
echo ""

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}ERROR: This script is designed for macOS only${NC}"
    exit 1
fi

# Check required tools
echo -e "${YELLOW}Checking requirements...${NC}"
MISSING_TOOLS=()
if ! command -v git >/dev/null 2>&1; then
    MISSING_TOOLS+=("git")
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo -e "${RED}ERROR: Missing required tools: ${MISSING_TOOLS[*]}${NC}"
    echo ""
    echo "Install missing tools:"
    for tool in "${MISSING_TOOLS[@]}"; do
        case "${tool}" in
            git)
                echo "  - Git: xcode-select --install (or install Xcode)"
                ;;
        esac
    done
    exit 1
fi

# Check recommended system libraries
echo -e "${YELLOW}Checking recommended system libraries...${NC}"
MISSING_LIBS=()
RECOMMENDED_LIBS=("libpng" "libjpeg" "freetype" "libxml2" "libzip" "imagemagick" "pkg-config")

if command -v brew >/dev/null 2>&1; then
    for lib in "${RECOMMENDED_LIBS[@]}"; do
        if ! brew list "${lib}" >/dev/null 2>&1; then
            MISSING_LIBS+=("${lib}")
        fi
    done
    
    if [ ${#MISSING_LIBS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Warning: Missing recommended libraries: ${MISSING_LIBS[*]}${NC}"
        echo "Install with: brew install ${MISSING_LIBS[*]}"
        echo ""
        if [ -t 0 ]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        else
            echo -e "${YELLOW}Non-interactive mode: Continuing anyway (build may fail)${NC}"
            sleep 2
        fi
    fi
fi

echo -e "${GREEN}✓ All required tools are available${NC}"
if [ ${#MISSING_LIBS[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All recommended libraries are available${NC}"
fi
echo ""

# Detect system resources for optimal build performance
echo -e "${YELLOW}Detecting system resources...${NC}"

# Detect CPU cores
if command -v sysctl >/dev/null 2>&1; then
    CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "2")
else
    CPU_CORES=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo "2")
fi

# Detect physical CPU cores (excluding hyperthreading)
PHYSICAL_CORES=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "${CPU_CORES}")

# Detect total RAM (in GB)
if command -v sysctl >/dev/null 2>&1; then
    TOTAL_RAM_GB=$(($(sysctl -n hw.memsize 2>/dev/null || echo "8589934592") / 1024 / 1024 / 1024))
else
    TOTAL_RAM_GB=8
fi

# Calculate optimal parallel jobs
PARALLEL_JOBS=$((PHYSICAL_CORES + 1))
if [ "${PARALLEL_JOBS}" -gt "${CPU_CORES}" ]; then
    PARALLEL_JOBS="${CPU_CORES}"
fi
if [ "${PARALLEL_JOBS}" -lt 2 ]; then
    PARALLEL_JOBS=2
fi

echo "System resources detected:"
echo "  CPU cores (logical): ${CPU_CORES}"
echo "  CPU cores (physical): ${PHYSICAL_CORES}"
echo "  Total RAM: ${TOTAL_RAM_GB} GB"
echo "  Optimal parallel jobs: ${PARALLEL_JOBS}"
echo ""

# Set Composer memory limit based on available RAM
COMPOSER_MEMORY_LIMIT=$((TOTAL_RAM_GB / 2))
if [ "${COMPOSER_MEMORY_LIMIT}" -gt 4 ]; then
    COMPOSER_MEMORY_LIMIT=4
fi
if [ "${COMPOSER_MEMORY_LIMIT}" -lt 1 ]; then
    COMPOSER_MEMORY_LIMIT=1
fi
export COMPOSER_MEMORY_LIMIT="${COMPOSER_MEMORY_LIMIT}G"

echo -e "${GREEN}Build optimization:${NC}"
echo "  Parallel build jobs: ${PARALLEL_JOBS}"
echo "  Composer memory limit: ${COMPOSER_MEMORY_LIMIT}"
echo ""

# Create temporary directory for building
TMP_DIR=$(mktemp -d)
BUILD_DIR="${TMP_DIR}/build"
mkdir -p "${BUILD_DIR}"

# Debug mode: preserve build artifacts on failure
if [[ "${DEBUG_MODE}" == "true" ]]; then
    echo -e "${YELLOW}DEBUG MODE ENABLED: Build artifacts will be preserved on failure${NC}"
fi

# Ensure cleanup on exit
CLEANUP_EXIT_CODE=0
cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "${TMP_DIR}" ]; then
        if [[ "${DEBUG_MODE}" == "true" ]] && [ ${CLEANUP_EXIT_CODE:-0} -ne 0 ]; then
            echo ""
            echo -e "${YELLOW}============================================================================${NC}"
            echo -e "${YELLOW}DEBUG MODE: Preserving build artifacts${NC}"
            echo -e "${YELLOW}============================================================================${NC}"
            echo ""
            echo "Build directory preserved at: ${TMP_DIR}"
            echo ""
        elif [[ "${DEBUG_MODE}" != "true" ]]; then
            rm -rf "${TMP_DIR}"
        fi
    fi
}

trap 'CLEANUP_EXIT_CODE=$?; cleanup; exit ${CLEANUP_EXIT_CODE}' EXIT INT TERM

cd "${BUILD_DIR}"

# Step 1: Prepare OpenEMR and create PHAR
echo -e "${YELLOW}Step 1/5: Preparing OpenEMR application...${NC}"
echo "Temporary directory: ${TMP_DIR}"
echo ""

OPENEMR_DIR="${BUILD_DIR}/openemr-source"
PHAR_FILE="${BUILD_DIR}/openemr.phar"

echo "Cloning OpenEMR ${OPENEMR_TAG}..."
MAX_RETRIES=3
RETRY_COUNT=0
while [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; do
    if git clone --depth 1 --branch "${OPENEMR_TAG}" https://github.com/openemr/openemr.git openemr-source; then
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; then
        echo -e "${YELLOW}Clone attempt ${RETRY_COUNT} failed. Retrying in 5 seconds...${NC}"
        sleep 5
        rm -rf openemr-source 2>/dev/null || true
    else
        echo -e "${RED}ERROR: Failed to clone OpenEMR after ${MAX_RETRIES} attempts${NC}"
        exit 1
    fi
done

cd openemr-source

# Prepare OpenEMR for PHAR creation
echo "Preparing application for PHAR creation..."
mkdir -p "${BUILD_DIR}/openemr-phar"

# Export clean version without .git
git archive HEAD | tar -x -C "${BUILD_DIR}/openemr-phar"

cd "${BUILD_DIR}/openemr-phar"

# Remove unneeded files to reduce size
echo "Removing unneeded files..."
rm -rf .git tests/ .github/ docs/ 2>/dev/null || true

# Install production dependencies
echo "Installing production dependencies..."
if [ -f "composer.json" ] && command -v composer >/dev/null 2>&1; then
    echo "Using ${PARALLEL_JOBS} parallel processes and ${COMPOSER_MEMORY_LIMIT} memory limit..."
    COMPOSER_MEMORY_LIMIT="${COMPOSER_MEMORY_LIMIT}" \
    COMPOSER_PROCESS_TIMEOUT=0 \
    composer install \
        --ignore-platform-reqs \
        --no-dev \
        --optimize-autoloader \
        --prefer-dist \
        --no-interaction \
        2>&1 | grep -v "^#" || {
        echo -e "${YELLOW}WARNING: Composer install had issues, but continuing...${NC}"
    }
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
        echo -e "${YELLOW}WARNING: Failed to install global npm deps${NC}"
        echo "Continuing anyway..."
    }
    
    # Install npm dependencies (WITHOUT --production flag to get devDependencies needed for building)
    echo "Installing npm dependencies (including devDependencies for build tools)..."
    NODE_OPTIONS="--max-old-space-size=$((TOTAL_RAM_GB * 512))" npm ci 2>&1 || {
        echo -e "${YELLOW}WARNING: npm ci had issues, trying npm install as fallback...${NC}"
        NODE_OPTIONS="--max-old-space-size=$((TOTAL_RAM_GB * 512))" npm install 2>&1 || {
            echo -e "${YELLOW}WARNING: npm install also had issues, but continuing...${NC}"
            echo -e "${YELLOW}(Some frontend dependencies may be missing, but OpenEMR core will still work)${NC}"
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
            echo -e "${GREEN}✓ Frontend assets built successfully (CSS and JavaScript compiled)${NC}"
        } || {
            echo -e "${YELLOW}WARNING: npm run build had issues${NC}"
        }
    else
        # Fallback: try gulp directly if npm run build doesn't exist
        if command -v gulp >/dev/null 2>&1 && ([ -f "gulpfile.js" ] || [ -f "Gulpfile.js" ]); then
            echo "Running gulp directly to build frontend assets..."
            NODE_OPTIONS="--max-old-space-size=$((TOTAL_RAM_GB * 512))" gulp 2>&1 && {
                BUILD_SUCCESS=true
                echo -e "${GREEN}✓ Gulp build completed successfully${NC}"
            } || {
                echo -e "${YELLOW}WARNING: gulp build had issues${NC}"
            }
        fi
    fi
    
    if [ "${BUILD_SUCCESS}" != "true" ]; then
        echo -e "${RED}ERROR: Frontend build failed!${NC}"
        echo -e "${RED}CSS and JavaScript assets were NOT compiled.${NC}"
        echo -e "${RED}OpenEMR will not have working styles or JavaScript.${NC}"
        echo ""
        echo "This is a critical issue. Please check:"
        echo "  - Node.js and npm are properly installed"
        echo "  - All npm dependencies installed correctly"
        echo "  - gulp-cli is installed globally"
        exit 1
    fi
    
    echo -e "${GREEN}Frontend build step completed successfully.${NC}"
fi

# Create PHAR file
echo "Creating PHAR archive..."
if command -v php >/dev/null 2>&1; then
    # Create a simple PHAR builder script
    cat > "${BUILD_DIR}/create-phar.php" << 'PHARBUILDER'
<?php
// Disable phar.readonly for this script
ini_set('phar.readonly', '0');

$pharFile = $argv[1];
$sourceDir = $argv[2];

// Clean up existing PHAR
if (file_exists($pharFile)) {
    unlink($pharFile);
}

// Create PHAR
$phar = new Phar($pharFile);
$phar->buildFromDirectory($sourceDir);
$phar->setStub($phar->createDefaultStub('interface/main/main.php'));
$phar->compressFiles(Phar::GZ);

echo "PHAR created: $pharFile\n";
PHARBUILDER

    # Run PHP with phar.readonly disabled
    php -d phar.readonly=0 "${BUILD_DIR}/create-phar.php" "${PHAR_FILE}" "${BUILD_DIR}/openemr-phar"
    
    if [ -f "${PHAR_FILE}" ]; then
        echo -e "${GREEN}✓ PHAR created: $(du -h "${PHAR_FILE}" | cut -f1)${NC}"
    else
        echo -e "${RED}ERROR: Failed to create PHAR file${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}WARNING: PHP not found. Skipping PHAR creation.${NC}"
    echo "You'll need PHP to create the PHAR file."
    echo "Install with: brew install php"
    exit 1
fi

echo ""

# Step 2: Download and setup Static PHP CLI (SPC)
echo -e "${YELLOW}Step 2/5: Setting up Static PHP CLI (SPC)...${NC}"

SPC_DIR="${BUILD_DIR}/spc"
ARCH=$(uname -m)
if [ "${ARCH}" = "arm64" ]; then
    SPC_ARCH="aarch64"
    SPC_OS="macos"
elif [ "${ARCH}" = "x86_64" ]; then
    SPC_ARCH="x86_64"
    SPC_OS="macos"
else
    echo -e "${RED}ERROR: Unsupported architecture: ${ARCH}${NC}"
    exit 1
fi

SPC_RELEASE="spc-${SPC_OS}-${SPC_ARCH}.tar.gz"

# Download URL for pinned Static PHP CLI version
# Version is pinned to ${STATIC_PHP_CLI_RELEASE_TAG} (default: 2.7.9) for stability
# Override by setting STATIC_PHP_CLI_RELEASE_TAG environment variable before running the script
SPC_URL="https://github.com/${STATIC_PHP_CLI_REPO}/releases/download/${STATIC_PHP_CLI_RELEASE_TAG}/${SPC_RELEASE}"
echo "Downloading Static PHP CLI ${STATIC_PHP_CLI_RELEASE_TAG} for ${SPC_OS}-${SPC_ARCH}..."

if command -v curl >/dev/null 2>&1; then
    curl -L -o "${BUILD_DIR}/${SPC_RELEASE}" "${SPC_URL}" || {
        echo -e "${RED}ERROR: Failed to download Static PHP CLI release ${STATIC_PHP_CLI_RELEASE_TAG}${NC}"
        echo "URL: ${SPC_URL}"
        echo ""
        echo "Please check:"
        echo "  1. The release tag exists: ${STATIC_PHP_CLI_RELEASE_TAG}"
        echo "  2. Your internet connection is working"
        echo "  3. GitHub is accessible"
        echo ""
        echo "To use a different version, set STATIC_PHP_CLI_RELEASE_TAG environment variable:"
        echo "  export STATIC_PHP_CLI_RELEASE_TAG=2.8.0"
        echo "  ./build-macos.sh"
        exit 1
    }
elif command -v wget >/dev/null 2>&1; then
    wget -O "${BUILD_DIR}/${SPC_RELEASE}" "${SPC_URL}" || {
        echo -e "${RED}ERROR: Failed to download Static PHP CLI${NC}"
        exit 1
    }
else
    echo -e "${RED}ERROR: Need curl or wget to download Static PHP CLI${NC}"
    exit 1
fi

echo "Extracting Static PHP CLI..."
tar -xzf "${BUILD_DIR}/${SPC_RELEASE}" -C "${BUILD_DIR}"
mv "${BUILD_DIR}/spc" "${SPC_DIR}" 2>/dev/null || true
chmod +x "${SPC_DIR}/spc" 2>/dev/null || chmod +x "${BUILD_DIR}/spc" 2>/dev/null || true

SPC_BIN=""
if [ -f "${SPC_DIR}/spc" ]; then
    SPC_BIN="${SPC_DIR}/spc"
elif [ -f "${BUILD_DIR}/spc" ]; then
    SPC_BIN="${BUILD_DIR}/spc"
else
    echo -e "${RED}ERROR: Could not find spc binary after extraction${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Static PHP CLI setup complete${NC}"
echo ""

# Step 3: Prepare SPC and download dependencies
echo -e "${YELLOW}Step 3/5: Preparing SPC and downloading dependencies...${NC}"

cd "${BUILD_DIR}"

# PHP extensions required by OpenEMR (use from environment or default)
PHP_EXTENSIONS="${PHP_EXTENSIONS:-bcmath,exif,gd,intl,ldap,mbstring,mysqli,opcache,openssl,pcntl,pdo_mysql,phar,redis,soap,sockets,zip,imagick}"

echo "Running SPC doctor check..."
"${SPC_BIN}" doctor --auto-fix || {
    echo -e "${YELLOW}Warning: SPC doctor check had issues${NC}"
}

echo ""
echo "Downloading PHP and extension sources..."
echo "This may take a few minutes..."
echo -e "${YELLOW}Note: GitHub API rate limiting may occur. If downloads fail, wait a few minutes and retry.${NC}"
echo ""
echo -e "${BLUE}[Output will stream to terminal]${NC}"
echo ""

# Try downloading with retries
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
        echo ""
        echo -e "${YELLOW}Download failed (attempt ${DOWNLOAD_RETRY_COUNT}/${MAX_DOWNLOAD_RETRIES}).${NC}"
        echo -e "${YELLOW}Waiting ${WAIT_TIME} seconds for GitHub rate limit reset before retrying...${NC}"
        sleep ${WAIT_TIME}
        echo "Retrying download..."
    else
        echo ""
        echo -e "${RED}ERROR: Failed to download dependencies after ${MAX_DOWNLOAD_RETRIES} attempts${NC}"
        echo "This is likely due to GitHub API rate limiting."
        echo "Solutions:"
        echo "  1. Wait 5-10 minutes and try again"
        echo "  2. Set GITHUB_TOKEN environment variable: export GITHUB_TOKEN=your_token"
        echo "  3. Check your internet connection"
        exit 1
    fi
done

echo -e "${GREEN}✓ Dependencies downloaded${NC}"
echo ""

# Step 4: Build static PHP binaries
echo -e "${YELLOW}Step 4/5: Building static PHP binaries...${NC}"
echo "This may take ${PARALLEL_JOBS}0-$((PARALLEL_JOBS * 15)) minutes depending on your system."
echo "Using ${PARALLEL_JOBS} parallel build jobs."
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📺 BUILD OUTPUT STREAMING TO TERMINAL${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

export MAKEFLAGS="-j${PARALLEL_JOBS}"
export MAKE_JOBS="${PARALLEL_JOBS}"
export NPROC="${PARALLEL_JOBS}"

echo "Building PHP CLI and MicroSFX..."
echo -e "${BLUE}[All build output will stream to terminal in real-time]${NC}"
echo ""

# Build - output streams directly to terminal
# Note: The CGI SAPI is built for use with CGI-based web servers (e.g., Apache with mod_cgi)
"${SPC_BIN}" build \
    --build-cli \
    --build-cgi \
    --build-micro \
    "${PHP_EXTENSIONS}"

echo -e "${GREEN}✓ Static PHP binaries built${NC}"
echo ""

# Step 5: Combine PHAR with MicroSFX
echo -e "${YELLOW}Step 5/5: Combining PHAR with MicroSFX...${NC}"

# Find the micro.sfx file
MICRO_SFX=""
if [ -f "${BUILD_DIR}/buildroot/bin/micro.sfx" ]; then
    MICRO_SFX="${BUILD_DIR}/buildroot/bin/micro.sfx"
elif [ -f "${BUILD_DIR}/static-php-cli/buildroot/bin/micro.sfx" ]; then
    MICRO_SFX="${BUILD_DIR}/static-php-cli/buildroot/bin/micro.sfx"
else
    # Search for it
    MICRO_SFX=$(find "${BUILD_DIR}" -name "micro.sfx" -type f 2>/dev/null | head -1)
fi

if [ -z "${MICRO_SFX}" ] || [ ! -f "${MICRO_SFX}" ]; then
    echo -e "${RED}ERROR: Could not find micro.sfx file${NC}"
    echo "Searched in: ${BUILD_DIR}"
    exit 1
fi

echo "Found micro.sfx at: ${MICRO_SFX}"
echo "Combining with PHAR..."

FINAL_BINARY_NAME="openemr-${OPENEMR_TAG}-macos-${ARCH}"
FINAL_BINARY="${SCRIPT_DIR}/${FINAL_BINARY_NAME}"

"${SPC_BIN}" micro:combine "${PHAR_FILE}" -O "${FINAL_BINARY}"

if [ -f "${FINAL_BINARY}" ]; then
    chmod +x "${FINAL_BINARY}"
    BINARY_SIZE=$(du -h "${FINAL_BINARY}" | cut -f1)
    echo -e "${GREEN}✓ Binary created: ${FINAL_BINARY_NAME} (${BINARY_SIZE})${NC}"
else
    echo -e "${RED}ERROR: Failed to create final binary${NC}"
    exit 1
fi

# Also copy PHP CLI binary and PHAR file for web server launcher
echo ""
echo "Setting up web server components..."
PHP_CLI_BINARY=""
if [ -f "${BUILD_DIR}/buildroot/bin/php" ]; then
    PHP_CLI_BINARY="${BUILD_DIR}/buildroot/bin/php"
elif [ -f "${BUILD_DIR}/static-php-cli/buildroot/bin/php" ]; then
    PHP_CLI_BINARY="${BUILD_DIR}/static-php-cli/buildroot/bin/php"
else
    PHP_CLI_BINARY=$(find "${BUILD_DIR}" -name "php" -type f -path "*/buildroot/bin/php" 2>/dev/null | head -1)
fi

if [ -n "${PHP_CLI_BINARY}" ] && [ -f "${PHP_CLI_BINARY}" ]; then
    # Copy to mac_os directory
    PHP_CLI_COPY="${SCRIPT_DIR}/php-cli-${OPENEMR_TAG}-macos-${ARCH}"
    cp "${PHP_CLI_BINARY}" "${PHP_CLI_COPY}"
    chmod +x "${PHP_CLI_COPY}"
    echo -e "${GREEN}✓ PHP CLI binary saved: $(basename "${PHP_CLI_COPY}")${NC}"
    
    # Also copy to project root for easier access
    PHP_CLI_ROOT="${PROJECT_ROOT}/php-cli-${OPENEMR_TAG}-macos-${ARCH}"
    cp "${PHP_CLI_BINARY}" "${PHP_CLI_ROOT}"
    chmod +x "${PHP_CLI_ROOT}"
    echo -e "${GREEN}✓ PHP CLI binary also saved to project root: $(basename "${PHP_CLI_ROOT}")${NC}"
fi

# Find and copy PHP CGI binary
PHP_CGI_BINARY=""
if [ -f "${BUILD_DIR}/buildroot/bin/php-cgi" ]; then
    PHP_CGI_BINARY="${BUILD_DIR}/buildroot/bin/php-cgi"
elif [ -f "${BUILD_DIR}/static-php-cli/buildroot/bin/php-cgi" ]; then
    PHP_CGI_BINARY="${BUILD_DIR}/static-php-cli/buildroot/bin/php-cgi"
else
    PHP_CGI_BINARY=$(find "${BUILD_DIR}" -name "php-cgi" -type f -path "*/buildroot/bin/php-cgi" 2>/dev/null | head -1)
fi

if [ -n "${PHP_CGI_BINARY}" ] && [ -f "${PHP_CGI_BINARY}" ]; then
    # Copy to mac_os directory
    PHP_CGI_COPY="${SCRIPT_DIR}/php-cgi-${OPENEMR_TAG}-macos-${ARCH}"
    cp "${PHP_CGI_BINARY}" "${PHP_CGI_COPY}"
    chmod +x "${PHP_CGI_COPY}"
    echo -e "${GREEN}✓ PHP CGI binary saved: $(basename "${PHP_CGI_COPY}")${NC}"
    
    # Also copy to project root for easier access
    PHP_CGI_ROOT="${PROJECT_ROOT}/php-cgi-${OPENEMR_TAG}-macos-${ARCH}"
    cp "${PHP_CGI_BINARY}" "${PHP_CGI_ROOT}"
    chmod +x "${PHP_CGI_ROOT}"
    echo -e "${GREEN}✓ PHP CGI binary also saved to project root: $(basename "${PHP_CGI_ROOT}")${NC}"
fi

# Copy PHAR file for extraction if needed
PHAR_COPY="${SCRIPT_DIR}/openemr-${OPENEMR_TAG}.phar"
if [ -f "${PHAR_FILE}" ]; then
    cp "${PHAR_FILE}" "${PHAR_COPY}"
    echo -e "${GREEN}✓ PHAR archive saved: $(basename "${PHAR_COPY}")${NC}"
    
    # Also copy to project root for easier access
    PHAR_ROOT="${PROJECT_ROOT}/openemr-${OPENEMR_TAG}.phar"
    cp "${PHAR_FILE}" "${PHAR_ROOT}"
    echo -e "${GREEN}✓ PHAR archive also saved to project root: $(basename "${PHAR_ROOT}")${NC}"
fi

# Check for php.ini file (used by web server launcher)
PHP_INI_FILE="${SCRIPT_DIR}/php.ini"
if [ -f "${PHP_INI_FILE}" ]; then
    echo -e "${GREEN}✓ PHP configuration file found: php.ini${NC}"
    echo "  Location: ${PHP_INI_FILE}"
    echo "  This file is used by the web server launcher"
    echo "  You can customize PHP settings by editing this file"
else
    echo -e "${YELLOW}Note: php.ini file not found at ${PHP_INI_FILE}${NC}"
    echo "  The web server launcher will use PHP defaults"
    echo "  Create a php.ini file to customize PHP settings"
fi

echo ""
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "Binary location: ${FINAL_BINARY}"
echo ""
echo "To run OpenEMR web server:"
echo "  ./run-web-server.sh [port]"
echo ""
echo "Example:"
echo "  ./run-web-server.sh 8080"
echo ""
echo "The web server launcher will:"
echo "  1. Extract the PHAR archive to serve individual files"
echo "  2. Start PHP's built-in server"
echo "  3. Make OpenEMR accessible at http://localhost:${PORT:-8080}"
echo ""
