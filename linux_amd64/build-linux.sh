#!/usr/bin/env bash
# ==============================================================================
# Build OpenEMR Static Binary for Linux (amd64) using Docker
# ==============================================================================
# This script builds a self-contained OpenEMR binary for Linux amd64 using
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
#   ./build-linux.sh v8_4_1
#   PHP_VERSION=8.4 ./build-linux.sh v8_4_1
#
# Requirements:
#   - Docker installed and running
#   - Internet connection for downloading dependencies during build
#
# The resulting binary will be in the linux_amd64/ directory.
# ==============================================================================

# ==============================================================================
# Version Configuration
# ==============================================================================
# All package versions are defined here as environment variables for easy
# maintenance and stability. Override these variables before running the script
# to use different versions.
#
# OpenEMR Configuration:
export OPENEMR_VERSION="${OPENEMR_VERSION:-v8_4_1}"
#
# Docker Base Image:
export DOCKER_BASE_IMAGE="${DOCKER_BASE_IMAGE:-ubuntu:24.04}"
#
# PHP Configuration:
# 8.5 is the latest stable line. The Docker image resolves it to the current
# patch (8.5.11 as of 2026-09-24) when building the host PHP used for PHAR creation.
# SPC also downloads that current 8.5 patch for the static binaries.
export PHP_VERSION="${PHP_VERSION:-8.5}"
#
# Static PHP CLI (SPC) Configuration:
# Pinned to the latest release, 2.8.5. Override STATIC_PHP_CLI_RELEASE_TAG to use another version.
export STATIC_PHP_CLI_REPO="${STATIC_PHP_CLI_REPO:-https://github.com/crazywhalecc/static-php-cli.git}"
export STATIC_PHP_CLI_BRANCH="${STATIC_PHP_CLI_BRANCH:-main}"
export STATIC_PHP_CLI_RELEASE_TAG="${STATIC_PHP_CLI_RELEASE_TAG:-2.8.5}"
#
# PHP Extensions (comma-separated list):
export PHP_EXTENSIONS="${PHP_EXTENSIONS:-bcmath,exif,gd,intl,ldap,mbstring,mysqli,opcache,openssl,pcntl,pdo_mysql,phar,redis,soap,sockets,zip,imagick,filter,curl,dom,fileinfo,simplexml,xmlreader,xmlwriter,xsl,ctype,calendar,tokenizer,iconv,sodium}"
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
echo -e "${GREEN}Building OpenEMR Static Binary for Linux (amd64) using Docker${NC}"
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
ARCH="x86_64"
TARGET_ARCH="amd64"

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
RUN apt-get update --allow-insecure-repositories && apt-get install -y \\
    --allow-unauthenticated \\
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

# Install Node.js 24 from the official tarball. NodeSource's apt setup fails
# under QEMU amd64 with "invalid signature" on Ubuntu InRelease files.
RUN set -eux; \\
    arch="\$(dpkg --print-architecture)"; \\
    case "\${arch}" in \\
        amd64) node_arch=x64 ;; \\
        arm64) node_arch=arm64 ;; \\
        *) echo "Unsupported architecture: \${arch}"; exit 1 ;; \\
    esac; \\
    node_tarball="\$(curl -fsSL https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt | awk -v a="\${node_arch}" '\$2 ~ ("node-v24.*linux-" a ".tar.xz") { print \$2; exit }')"; \\
    test -n "\${node_tarball}"; \\
    curl -fsSL "https://nodejs.org/dist/latest-v24.x/\${node_tarball}" -o /tmp/node.tar.xz; \\
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1; \\
    rm /tmp/node.tar.xz; \\
    node -v; \\
    npm -v

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

if docker image inspect openemr-builder-amd64:latest >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Reusing existing Docker image openemr-builder-amd64:latest${NC}"
    echo ""
else
    echo "Building Docker image for Linux amd64 build..."
    echo "Using PHP version: ${PHP_VERSION}"
    echo "Using base image: ${DOCKER_BASE_IMAGE}"
    docker build --platform linux/amd64 \
        --build-arg DOCKER_BASE_IMAGE="${DOCKER_BASE_IMAGE}" \
        --build-arg PHP_VERSION_MAJOR_MINOR="${PHP_VERSION}" \
        -t openemr-builder-amd64:latest \
        -f "${DOCKERFILE}" \
        "${SCRIPT_DIR}" || {
        echo -e "${RED}ERROR: Failed to build Docker image${NC}"
        exit 1
    }

    echo -e "${GREEN}✓ Docker image built${NC}"
    echo ""
fi

# Create build script that will run inside Docker
BUILD_SCRIPT="${SCRIPT_DIR}/docker-build-internal.sh"
cat > "${BUILD_SCRIPT}" << 'BUILD_SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

OPENEMR_TAG="${1:-v8_4_1}"
PHP_VERSION="${2:-8.5}"
STATIC_PHP_CLI_REPO="${3:-https://github.com/crazywhalecc/static-php-cli.git}"
STATIC_PHP_CLI_BRANCH="${4:-main}"
STATIC_PHP_CLI_RELEASE_TAG="${5:-2.8.5}"
PHP_EXTENSIONS="${6:-bcmath,exif,gd,intl,ldap,mbstring,mysqli,opcache,openssl,pcntl,pdo_mysql,phar,redis,soap,sockets,zip,imagick,filter,curl,dom,fileinfo,simplexml,xmlreader,xmlwriter,xsl,ctype,calendar,tokenizer,iconv,sodium}"
ARCH="x86_64"
TARGET_ARCH="amd64"

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

# Reuse a completed composer+npm tree on the host bind mount. A full
# QEMU reinstall of google/apiclient-services + webpack is very expensive.
if [ -f /build/openemr-phar/vendor/autoload.php ] \
    && [ -f /build/openemr-phar/oauth2/authorize.php ] \
    && [ -f /build/openemr-phar/public/themes/style_light.css ]; then
    echo "Reusing existing OpenEMR staging tree (vendor + compiled frontend already present)"
    cd /build/openemr-phar
else
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
        COMPOSER_OK=false
        COMPOSER_ATTEMPT=0
        COMPOSER_MAX_ATTEMPTS=3
        while [ ${COMPOSER_ATTEMPT} -lt ${COMPOSER_MAX_ATTEMPTS} ]; do
            COMPOSER_ATTEMPT=$((COMPOSER_ATTEMPT + 1))
            echo "Composer install attempt ${COMPOSER_ATTEMPT}/${COMPOSER_MAX_ATTEMPTS}..."
            if COMPOSER_MEMORY_LIMIT="${COMPOSER_MEMORY_LIMIT}" \
                COMPOSER_PROCESS_TIMEOUT=0 \
                composer install \
                    --ignore-platform-reqs \
                    --no-dev \
                    --optimize-autoloader \
                    --prefer-dist \
                    --no-interaction; then
                COMPOSER_OK=true
                break
            fi
            echo "Composer install failed (network timeouts are common under QEMU)"
            if [ ${COMPOSER_ATTEMPT} -lt ${COMPOSER_MAX_ATTEMPTS} ]; then
                sleep $((COMPOSER_ATTEMPT * 15))
            fi
        done
        if [ "${COMPOSER_OK}" != "true" ]; then
            echo "ERROR: composer install failed after ${COMPOSER_MAX_ATTEMPTS} attempts"
            exit 1
        fi
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
fi

echo "Creating PHAR archive..."
# Pack from a container-local copy. QEMU amd64 + Docker Desktop virtiofs
# can throw ENOENT from RecursiveDirectoryIterator on listed dirs (oauth2).
# Also drop node_modules / webpack cache; they are not needed at runtime.
PACK_DIR="/var/tmp/openemr-phar-pack"
rm -rf "${PACK_DIR}"
mkdir -p "${PACK_DIR}"
tar -C /build/openemr-phar \
    --exclude=node_modules \
    --exclude=.webpack-cache \
    --exclude=.git \
    -cf - . | tar -C "${PACK_DIR}" -xf -
if [ ! -f "${PACK_DIR}/oauth2/authorize.php" ]; then
    echo "ERROR: oauth2/authorize.php missing from PHAR staging copy"
    exit 1
fi

cat > /build/create-phar.php << 'PHARBUILDER'
<?php
ini_set('memory_limit', '2048M');
ini_set('phar.readonly', '0');
$pharFile = $argv[1];
$sourceDir = rtrim($argv[2], '/');
if (file_exists($pharFile)) {
    unlink($pharFile);
}

$skipNames = ['node_modules' => true, '.webpack-cache' => true, '.git' => true];

final class TolerantRecursiveDirectoryIterator extends RecursiveDirectoryIterator
{
    public function hasChildren(bool $allowLinks = false): bool
    {
        if (!parent::hasChildren($allowLinks)) {
            return false;
        }
        $path = $this->getPathname();
        if (is_link($path) || !is_dir($path)) {
            return false;
        }
        $dh = @opendir($path);
        if ($dh === false) {
            fwrite(STDERR, "WARNING: skipping unreadable directory: {$path}\n");
            return false;
        }
        closedir($dh);
        return true;
    }
}

$flags = FilesystemIterator::SKIP_DOTS | FilesystemIterator::UNIX_PATHS;
$inner = new TolerantRecursiveDirectoryIterator($sourceDir, $flags);
$filtered = new RecursiveCallbackFilterIterator($inner, static function ($current) use ($skipNames) {
    return !isset($skipNames[$current->getFilename()]);
});
$iter = new RecursiveIteratorIterator($filtered, RecursiveIteratorIterator::LEAVES_ONLY);

$map = [];
foreach ($iter as $file) {
    $path = $file->getPathname();
    if (!$file->isFile() || !is_readable($path)) {
        continue;
    }
    $rel = substr($path, strlen($sourceDir) + 1);
    $map[$rel] = $path;
}

if (!isset($map['oauth2/authorize.php'])) {
    fwrite(STDERR, "ERROR: oauth2/authorize.php was not collected for the PHAR\n");
    exit(1);
}

$phar = new Phar($pharFile);
$phar->buildFromIterator(new ArrayIterator($map));
$phar->setStub($phar->createDefaultStub('interface/main/main.php'));
$phar->compressFiles(Phar::GZ);
echo "PHAR created: $pharFile (" . count($map) . " files)\n";
PHARBUILDER

PHAR_TMP="/var/tmp/openemr.phar"
rm -f "${PHAR_TMP}"
php -d memory_limit=2048M -d phar.readonly=0 /build/create-phar.php "${PHAR_TMP}" "${PACK_DIR}"
cp -f "${PHAR_TMP}" "${PHAR_FILE}"
rm -rf "${PACK_DIR}" "${PHAR_TMP}"

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
    
    # Clone at the pinned release tag
    if [ -n "${STATIC_PHP_CLI_RELEASE_TAG}" ]; then
        if git clone --depth 1 --branch "${STATIC_PHP_CLI_RELEASE_TAG}" "${STATIC_PHP_CLI_REPO}" "${SPC_BUILD_DIR}"; then
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

# musl-cross `ar` can fail under Docker Desktop overlay with:
#   x86_64-linux-musl-ar: unable to copy file '.libs/libsodium.a'; reason: No error information
# Archive format is toolchain-agnostic, so retry then fall back to host GNU ar.
if [ -x /usr/local/musl/bin/x86_64-linux-musl-ar ]; then
    echo "Installing resilient ar wrapper for musl toolchain..."
    mv /usr/local/musl/bin/x86_64-linux-musl-ar /usr/local/musl/bin/x86_64-linux-musl-ar.real
    cat > /usr/local/musl/bin/x86_64-linux-musl-ar << 'AR_WRAPPER_EOF'
#!/usr/bin/env bash
REAL_AR="/usr/local/musl/bin/x86_64-linux-musl-ar.real"
HOST_AR="/usr/bin/ar"
for attempt in 1 2 3; do
    if "${REAL_AR}" "$@"; then
        exit 0
    fi
    echo "x86_64-linux-musl-ar failed (attempt ${attempt}/3), retrying..." >&2
    sleep "${attempt}"
done
if [ -x "${HOST_AR}" ]; then
    echo "x86_64-linux-musl-ar failed after retries; falling back to ${HOST_AR}" >&2
    exec "${HOST_AR}" "$@"
fi
exit 1
AR_WRAPPER_EOF
    chmod +x /usr/local/musl/bin/x86_64-linux-musl-ar
fi

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
        WAIT_TIME=$((DOWNLOAD_RETRY_COUNT * 60))
        echo "Download failed (attempt ${DOWNLOAD_RETRY_COUNT}/${MAX_DOWNLOAD_RETRIES})."
        echo "Waiting ${WAIT_TIME} seconds before retrying (GitHub rate limits reset slowly)..."
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
MAX_BUILD_RETRIES=2
BUILD_RETRY_COUNT=0
while [ ${BUILD_RETRY_COUNT} -le ${MAX_BUILD_RETRIES} ]; do
    if "${SPC_BIN}" build \
        --build-cli \
        --build-cgi \
        --build-fpm \
        --build-micro \
        --debug \
        "${PHP_EXTENSIONS}"; then
        break
    fi
    BUILD_RETRY_COUNT=$((BUILD_RETRY_COUNT + 1))
    if [ ${BUILD_RETRY_COUNT} -le ${MAX_BUILD_RETRIES} ]; then
        echo "SPC build failed (attempt ${BUILD_RETRY_COUNT}/${MAX_BUILD_RETRIES}). Retrying..."
        export SPC_CONCURRENCY=1
        export MAKEFLAGS="-j1"
        export MAKE_JOBS="1"
    else
        echo "ERROR: Failed to build static PHP after $((MAX_BUILD_RETRIES + 1)) attempts"
        exit 1
    fi
done

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

# Copy PHP CLI, PHP CGI and PHAR
# SPC build creates buildroot in current directory, search both /tmp and /build
PHP_CLI_BINARY=$(find /tmp /build -name "php" -type f -path "*/buildroot/bin/php" 2>/dev/null | head -1)
if [ -n "${PHP_CLI_BINARY}" ] && [ -f "${PHP_CLI_BINARY}" ]; then
    cp "${PHP_CLI_BINARY}" "/output/php-cli-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    chmod +x "/output/php-cli-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    echo "✓ PHP CLI binary saved"
fi

PHP_CGI_BINARY=$(find /tmp /build -name "php-cgi" -type f -path "*/buildroot/bin/php-cgi" 2>/dev/null | head -1)
if [ -n "${PHP_CGI_BINARY}" ] && [ -f "${PHP_CGI_BINARY}" ]; then
    cp "${PHP_CGI_BINARY}" "/output/php-cgi-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    chmod +x "/output/php-cgi-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    echo "✓ PHP CGI binary saved"
fi

PHP_FPM_BINARY=$(find /tmp /build -name "php-fpm" -type f -path "*/buildroot/bin/php-fpm" 2>/dev/null | head -1)
if [ -n "${PHP_FPM_BINARY}" ] && [ -f "${PHP_FPM_BINARY}" ]; then
    cp "${PHP_FPM_BINARY}" "/output/php-fpm-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    chmod +x "/output/php-fpm-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    echo "✓ PHP FPM binary saved"
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

# SPC downloads and compiles into /tmp. Docker Desktop's VM disk is often
# too small (this host was at 96% / 2GB free), so keep that work on the host.
SPC_WORKDIR="${SCRIPT_DIR}/.spc-workdir"
mkdir -p "${SPC_WORKDIR}/musl"

# Unauthenticated GitHub API is 60 req/hour; SPC download hits it per source.
if [ -z "${GITHUB_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
    GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
    export GITHUB_TOKEN
fi

echo "Starting Docker build container..."
echo "This may take 30-60 minutes depending on your system."
echo ""

# Run the build inside Docker
# QEMU amd64 on Apple Silicon: cap at 8GB so the native arm64 build keeps RAM.
CONTAINER_NAME="openemr-builder-amd64-$(date +%s)"
DOCKER_ENV_ARGS=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    DOCKER_ENV_ARGS+=(-e GITHUB_TOKEN)
    echo "Using GITHUB_TOKEN for SPC source downloads"
fi
docker run --name "${CONTAINER_NAME}" \
    --platform linux/amd64 \
    --memory=8g \
    --memory-swap=8g \
    ${DOCKER_ENV_ARGS[@]+"${DOCKER_ENV_ARGS[@]}"} \
    -v "${SCRIPT_DIR}:/build" \
    -v "${OUTPUT_DIR}:/output" \
    -v "${SPC_WORKDIR}:/tmp" \
    -v "${SPC_WORKDIR}/musl:/usr/local/musl" \
    -w /build \
    openemr-builder-amd64:latest \
    bash /build/docker-build-internal.sh "${OPENEMR_TAG}" "${PHP_VERSION}" "${STATIC_PHP_CLI_REPO}" "${STATIC_PHP_CLI_BRANCH}" "${STATIC_PHP_CLI_RELEASE_TAG}" "${PHP_EXTENSIONS}" || {
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
PHP_CLI_ROOT_BINARY="${SCRIPT_DIR}/php-cli-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
PHP_CGI_ROOT_BINARY="${SCRIPT_DIR}/php-cgi-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
PHAR_FILE="${SCRIPT_DIR}/openemr-${OPENEMR_TAG}.phar"

if [ -f "${FINAL_BINARY}" ]; then
    BINARY_ROOT="${PROJECT_ROOT}/openemr-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    cp "${FINAL_BINARY}" "${BINARY_ROOT}"
    chmod +x "${BINARY_ROOT}"
    BINARY_SIZE=$(du -h "${BINARY_ROOT}" | cut -f1)
    echo -e "${GREEN}✓ Binary also saved to project root: $(basename "${BINARY_ROOT}") (${BINARY_SIZE})${NC}"
fi

if [ -f "${PHP_CLI_ROOT_BINARY}" ]; then
    PHP_CLI_ROOT="${PROJECT_ROOT}/php-cli-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    cp "${PHP_CLI_ROOT_BINARY}" "${PHP_CLI_ROOT}"
    chmod +x "${PHP_CLI_ROOT}"
    echo -e "${GREEN}✓ PHP CLI also saved to project root: $(basename "${PHP_CLI_ROOT}")${NC}"
fi

if [ -f "${PHP_CGI_ROOT_BINARY}" ]; then
    PHP_CGI_ROOT="${PROJECT_ROOT}/php-cgi-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    cp "${PHP_CGI_ROOT_BINARY}" "${PHP_CGI_ROOT}"
    chmod +x "${PHP_CGI_ROOT}"
    echo -e "${GREEN}✓ PHP CGI also saved to project root: $(basename "${PHP_CGI_ROOT}")${NC}"
fi

PHP_FPM_ROOT_BINARY="${SCRIPT_DIR}/php-fpm-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
if [ -f "${PHP_FPM_ROOT_BINARY}" ]; then
    PHP_FPM_ROOT="${PROJECT_ROOT}/php-fpm-${OPENEMR_TAG}-linux-${TARGET_ARCH}"
    cp "${PHP_FPM_ROOT_BINARY}" "${PHP_FPM_ROOT}"
    chmod +x "${PHP_FPM_ROOT}"
    echo -e "${GREEN}✓ PHP FPM also saved to project root: $(basename "${PHP_FPM_ROOT}")${NC}"
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
