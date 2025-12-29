#!/usr/bin/env bash
# ==============================================================================
# Build OpenEMR Static Binary for FreeBSD using QEMU on macOS
# ==============================================================================
# This script builds a self-contained OpenEMR binary for FreeBSD by:
# 1. Setting up a FreeBSD VM using QEMU on macOS
# 2. Running the build process inside the FreeBSD VM using Static PHP CLI (SPC)
# 3. Copying the resulting binary back to macOS
#
# Requirements:
#   - macOS (Darwin) with Apple Silicon or Intel
#   - QEMU installed via Homebrew
#   - FreeBSD VM image (will be downloaded automatically)
#   - Internet connection for downloading dependencies
#
# Usage:
#   ./build-freebsd.sh [openemr_version] [freebsd_version]
#
# Example:
#   ./build-freebsd.sh v7_0_4 15.0
# ==============================================================================

# ==============================================================================
# Version Configuration
# ==============================================================================
export OPENEMR_VERSION="${OPENEMR_VERSION:-v7_0_4}"
export FREEBSD_VERSION="${FREEBSD_VERSION:-15.0}"
export PHP_VERSION="${PHP_VERSION:-8.5}"
export STATIC_PHP_CLI_RELEASE_TAG="${STATIC_PHP_CLI_RELEASE_TAG:-2.7.9}"
export STATIC_PHP_CLI_REPO="${STATIC_PHP_CLI_REPO:-crazywhalecc/static-php-cli}"
export PHP_EXTENSIONS="${PHP_EXTENSIONS:-bcmath,exif,gd,intl,ldap,mbstring,mysqli,opcache,openssl,pcntl,pdo_mysql,phar,redis,soap,sockets,zip,imagick,filter,curl,dom,fileinfo,simplexml,xmlreader,xmlwriter,xsl,ctype,calendar,tokenizer}"

# Build-time dependencies for the VM environment
export FREEBSD_PHP_PKG="php83"
export FREEBSD_PHP_EXTENSIONS_PKG="php83-extensions php83-zlib php83-zip"
export FREEBSD_PHP_COMPOSER_PKG="php83-composer"
export FREEBSD_NODE_PKG="node22"
export FREEBSD_NPM_PKG="npm-node22"
export FREEBSD_IMAGEMAGICK_PKG="ImageMagick7"
export FREEBSD_GCC_PKG="gcc13"
export FREEBSD_PYTHON_PKG="python311"

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Auto-detect CA bundle for curl if needed
if ! curl -s -f https://google.com >/dev/null 2>&1; then
    for cert in "/etc/ssl/cert.pem" "/opt/homebrew/etc/ca-certificates/cert.pem" "/usr/local/etc/ca-certificates/cert.pem" "/etc/pki/tls/certs/ca-bundle.crt"; do
        if [ -f "$cert" ] && curl --cacert "$cert" -s -f https://google.com >/dev/null 2>&1; then
            export CURL_CA_BUNDLE="$cert"
            break
        fi
    done
fi

# Handle arguments
DEBUG_MODE=false
OPENEMR_TAG="${OPENEMR_VERSION}"
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug) DEBUG_MODE=true; shift ;;
        -h|--help) echo "Usage: $0 [openemr_version] [freebsd_version] [php_version] [--debug]"; exit 0 ;;
        *)
            if [[ -z "${OPENEMR_TAG:-}" || "${OPENEMR_TAG}" == "${OPENEMR_VERSION}" ]]; then OPENEMR_TAG="$1"
            elif [[ "${FREEBSD_VERSION}" == "15.0" ]]; then FREEBSD_VERSION="$1"
            else PHP_VERSION="$1"; fi
            shift
            ;;
    esac
done

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Building OpenEMR Static Binary for FreeBSD using QEMU${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo "OpenEMR: ${OPENEMR_TAG}, FreeBSD: ${FREEBSD_VERSION}, PHP: ${PHP_VERSION}, SPC: ${STATIC_PHP_CLI_RELEASE_TAG}"

# Detect architecture
ARCH=$(uname -m)
if [ "${ARCH}" = "arm64" ]; then
    QEMU_ARCH="aarch64"; FREEBSD_ARCH="arm64"
    echo "Detected: Apple Silicon (ARM64)"
else
    QEMU_ARCH="x86_64"; FREEBSD_ARCH="amd64"
    echo "Detected: Intel (x86_64)"
fi

# Resources
CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "4")
TOTAL_RAM_GB=$(($(sysctl -n hw.memsize 2>/dev/null || echo "8589934592") / 1024 / 1024 / 1024))
VM_RAM_GB=$((TOTAL_RAM_GB / 2)); [ "${VM_RAM_GB}" -lt 4 ] && VM_RAM_GB=4; [ "${VM_RAM_GB}" -gt 16 ] && VM_RAM_GB=16

# Temp dirs
TMP_DIR="${SCRIPT_DIR}/build-tmp"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"
BUILD_DIR="${TMP_DIR}/build"; VM_DIR="${TMP_DIR}/vm"; SHARED_DIR="${TMP_DIR}/shared"
mkdir -p "${BUILD_DIR}" "${VM_DIR}" "${SHARED_DIR}"

# Cleanup
HTTP_SERVER_PID=""
QEMU_PID=""
cleanup() {
    EXIT_CODE=$?
    echo -e "${YELLOW}Cleaning up resources...${NC}"
    if [ -n "${HTTP_SERVER_PID:-}" ]; then kill "${HTTP_SERVER_PID}" 2>/dev/null || true; fi
    if [ -n "${QEMU_PID:-}" ]; then kill -TERM "${QEMU_PID}" 2>/dev/null || true; fi
    if [[ ("${DEBUG_MODE}" == "true" || ${EXIT_CODE} -ne 0) && -d "${TMP_DIR}" ]]; then
        echo "Build directory preserved at: ${TMP_DIR}"
        [ -f "${TMP_DIR}/qemu.log" ] && echo "QEMU Log: ${TMP_DIR}/qemu.log"
        [ -f "${TMP_DIR}/expect.log" ] && echo "Expect Log: ${TMP_DIR}/expect.log"
    else
        rm -rf "${TMP_DIR}"
    fi
    echo -e "${GREEN}Cleanup complete.${NC}"
}
trap cleanup EXIT INT TERM

# Step 1: VM Image
echo -e "${YELLOW}Step 1/5: Setting up FreeBSD VM image...${NC}"
VM_ARCH="${FREEBSD_ARCH}"; [ "${FREEBSD_ARCH}" = "arm64" ] && VM_ARCH="aarch64"
FREEBSD_IMAGE_NAME="FreeBSD-${FREEBSD_VERSION}-RELEASE-${FREEBSD_ARCH}-${VM_ARCH}-ufs.qcow2"
FREEBSD_IMAGE_URL="https://download.freebsd.org/releases/VM-IMAGES/${FREEBSD_VERSION}-RELEASE/${VM_ARCH}/Latest/${FREEBSD_IMAGE_NAME}.xz"
FREEBSD_IMAGE="${VM_DIR}/${FREEBSD_IMAGE_NAME}"

if [ ! -f "${FREEBSD_IMAGE}" ]; then
    echo "Downloading FreeBSD ${FREEBSD_VERSION} image..."
    MAX_RETRIES=5
    RETRY_COUNT=0
    DOWNLOAD_SUCCESS=false
    
    while [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; do
        echo "Attempt $((RETRY_COUNT + 1)) of ${MAX_RETRIES}..."
        # Use simple curl, CA bundle should be auto-detected or set by CURL_CA_BUNDLE env var
        if curl -L -f -o "${FREEBSD_IMAGE}.xz" "${FREEBSD_IMAGE_URL}"; then
            if [ -f "${FREEBSD_IMAGE}.xz" ]; then
                echo "Extracting image..."
                if xz -d "${FREEBSD_IMAGE}.xz"; then
                    DOWNLOAD_SUCCESS=true
                    break
                fi
            fi
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; then
            echo -e "${YELLOW}Download/extraction failed. Retrying in 5 seconds...${NC}"
            sleep 5
            rm -f "${FREEBSD_IMAGE}.xz" 2>/dev/null || true
        fi
    done

    if [ "${DOWNLOAD_SUCCESS}" = "false" ]; then
        echo -e "${RED}ERROR: Failed to download/extract FreeBSD image after ${MAX_RETRIES} attempts${NC}"
        exit 1
    fi

    qemu-img resize "${FREEBSD_IMAGE}" 30G
    echo "Image resized."
else
    echo "Using existing FreeBSD image."
fi

# Step 2: Build script for VM
echo -e "${YELLOW}Step 2/5: Preparing build script for FreeBSD VM...${NC}"

# Create environment file for VM
cat > "${SHARED_DIR}/env.sh" << ENVFILE
export OPENEMR_TAG='${OPENEMR_TAG}'
export PHP_VERSION='${PHP_VERSION}'
export ARCH='${FREEBSD_ARCH}'
export STATIC_PHP_CLI_RELEASE_TAG='${STATIC_PHP_CLI_RELEASE_TAG}'
export STATIC_PHP_CLI_REPO='${STATIC_PHP_CLI_REPO}'
export PHP_EXTENSIONS='${PHP_EXTENSIONS}'
export FREEBSD_PHP_PKG='${FREEBSD_PHP_PKG}'
export FREEBSD_PHP_EXTENSIONS_PKG='${FREEBSD_PHP_EXTENSIONS_PKG}'
export FREEBSD_PHP_COMPOSER_PKG='${FREEBSD_PHP_COMPOSER_PKG}'
export FREEBSD_NODE_PKG='${FREEBSD_NODE_PKG}'
export FREEBSD_NPM_PKG='${FREEBSD_NPM_PKG}'
export FREEBSD_IMAGEMAGICK_PKG='${FREEBSD_IMAGEMAGICK_PKG}'
export FREEBSD_GCC_PKG='${FREEBSD_GCC_PKG}'
export FREEBSD_PYTHON_PKG='${FREEBSD_PYTHON_PKG}'
ENVFILE

cat > "${SHARED_DIR}/freebsd-build.sh" << 'FREEBUILD'
#!/usr/local/bin/bash
set -euo pipefail
NC='\033[0m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'

# Source environment
if [ -f /tmp/env.sh ]; then source /tmp/env.sh; fi

echo -e "${GREEN}Starting build inside FreeBSD VM...${NC}"
export ASSUME_ALWAYS_YES=yes
export COMPOSER_ALLOW_SUPERUSER=1
pkg update

# Install all necessary packages for building PHP and OpenEMR
pkg install -y \
    git \
    ${FREEBSD_PHP_PKG} \
    ${FREEBSD_PHP_EXTENSIONS_PKG} \
    ${FREEBSD_PHP_COMPOSER_PKG} \
    ${FREEBSD_NODE_PKG} \
    ${FREEBSD_NPM_PKG} \
    curl \
    wget \
    gmake \
    autoconf \
    automake \
    libtool \
    pkgconf \
    bison \
    re2c \
    libxml2 \
    libxslt \
    icu \
    oniguruma \
    sqlite3 \
    openssl \
    libsodium \
    libzip \
    libiconv \
    gettext-runtime \
    gettext-tools \
    png \
    libjpeg-turbo \
    freetype2 \
    webp \
    bzip2 \
    ${FREEBSD_IMAGEMAGICK_PKG} \
    ${FREEBSD_GCC_PKG} \
    llvm \
    ${FREEBSD_PYTHON_PKG} \
    bash

# Ensure php symlink exists for shebangs
if [ ! -f /usr/local/bin/php ]; then ln -sf /usr/local/bin/php83 /usr/local/bin/php; fi

mkdir -p /build/artifacts
cd /build

# 1. Prepare OpenEMR Source and PHAR
echo -e "${YELLOW}Preparing OpenEMR PHAR...${NC}"
rm -rf openemr-source openemr-phar
git clone --depth 1 --branch "${OPENEMR_TAG}" https://github.com/openemr/openemr.git openemr-source
cd openemr-source
mkdir -p /build/openemr-phar
git archive HEAD | tar -x -C /build/openemr-phar
cd /build/openemr-phar
rm -rf .git tests/ .github/ docs/
composer install --ignore-platform-reqs --no-dev --optimize-autoloader --prefer-dist --no-interaction

if [ -f "package.json" ]; then
    echo -e "${YELLOW}Running npm build...${NC}"
    npm install -g napa gulp-cli 2>&1 | tee /build/npm-install-global.log
    (npm ci || npm install) 2>&1 | tee /build/npm-install.log
    # Filter Sass warnings aggressively to prevent serial console overflow.
    (npm run build 2>&1 | grep -Ei "Starting|Finished|Error|fatal" || true) | tee /build/npm-build.log
fi

cat > /build/create-phar.php << 'PHARBUILD'
<?php
ini_set('phar.readonly', '0');
$phar = new Phar($argv[1]);
$phar->buildFromDirectory($argv[2]);
$phar->setStub($phar->createDefaultStub('interface/main/main.php'));
$phar->compressFiles(Phar::GZ);
PHARBUILD
php -d phar.readonly=0 /build/create-phar.php /build/openemr.phar /build/openemr-phar

# 2. Build PHP from Source
echo -e "${YELLOW}Building PHP ${PHP_VERSION} from source...${NC}"
PHP_SRC_DIR="/build/php-src"
PHP_INSTALL_DIR="/build/php-static"
mkdir -p "${PHP_INSTALL_DIR}"

# Download PHP source
PHP_TARBALL="php-${PHP_VERSION}.tar.xz"
PHP_URL="https://www.php.net/distributions/${PHP_TARBALL}"

if ! fetch -o "/build/${PHP_TARBALL}" "${PHP_URL}" 2>/dev/null; then
    echo "Release tarball not found, trying GitHub for PHP ${PHP_VERSION}..."
    git clone --depth=1 --branch "PHP-${PHP_VERSION}" https://github.com/php/php-src.git "${PHP_SRC_DIR}" || \
    git clone --depth=1 https://github.com/php/php-src.git "${PHP_SRC_DIR}"
else
    tar -xf "/build/${PHP_TARBALL}" -C /build
    mv /build/php-${PHP_VERSION}* "${PHP_SRC_DIR}"
fi

cd "${PHP_SRC_DIR}"
[ -f "buildconf" ] && ./buildconf --force

# Compiler flags for FreeBSD
export CFLAGS="-O2 -I/usr/local/include"
export LDFLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib"
export LIBS="-lm -lpthread -lstdc++ -lintl -liconv -lz"

./configure \
    --prefix="${PHP_INSTALL_DIR}" \
    --enable-cli \
    --enable-cgi \
    --enable-fpm \
    --enable-bcmath \
    --enable-calendar \
    --enable-exif \
    --enable-ftp \
    --enable-intl \
    --enable-mbstring \
    --enable-mysqlnd \
    --enable-opcache \
    --enable-pcntl \
    --enable-pdo \
    --enable-soap \
    --enable-sockets \
    --with-gettext=/usr/local \
    --with-mhash \
    --with-mysqli=mysqlnd \
    --with-openssl=/usr/local \
    --with-pdo-mysql=mysqlnd \
    --with-sodium=/usr/local \
    --with-xsl=/usr/local \
    --with-zip \
    --with-zlib \
    --with-curl \
    --with-pear \
    --enable-phar

gmake -j$(sysctl -n hw.ncpu)
gmake install

# 3. Create Distribution Package
echo -e "${YELLOW}Creating distribution package...${NC}"
DIST_NAME="openemr-${OPENEMR_TAG}-freebsd-${ARCH}"
DIST_DIR="/build/${DIST_NAME}"
mkdir -p "${DIST_DIR}/lib" "${DIST_DIR}/bin"

cp "${PHP_INSTALL_DIR}/bin/php" "${DIST_DIR}/bin/php"
cp "${PHP_INSTALL_DIR}/bin/php-cgi" "${DIST_DIR}/bin/php-cgi"
cp "${PHP_INSTALL_DIR}/sbin/php-fpm" "${DIST_DIR}/bin/php-fpm"
cp /build/openemr.phar "${DIST_DIR}/openemr.phar"

# Bundle libraries for all binaries
for bin in "${DIST_DIR}/bin/php" "${DIST_DIR}/bin/php-cgi" "${DIST_DIR}/bin/php-fpm"; do
    if [ -f "$bin" ]; then
        ldd "$bin" | grep "=>" | awk '{print $3}' | while read lib; do
            if [[ "$lib" == /usr/local/* ]] && [ -f "$lib" ]; then
                # Avoid duplicates
                lib_name=$(basename "$lib")
                if [ ! -f "${DIST_DIR}/lib/${lib_name}" ]; then
                    cp "$lib" "${DIST_DIR}/lib/"
                fi
            fi
        done
    fi
done

# Launcher
cat > "${DIST_DIR}/openemr" << 'LAUNCHER'
#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="${SCRIPT_DIR}/lib:${LD_LIBRARY_PATH:-}"
exec "${SCRIPT_DIR}/bin/php" "${SCRIPT_DIR}/openemr.phar" "$@"
LAUNCHER
chmod +x "${DIST_DIR}/openemr"

cd /build
tar -czf "/build/artifacts/${DIST_NAME}.tar.gz" "${DIST_NAME}"
cp /build/openemr.phar "/build/artifacts/openemr-${OPENEMR_TAG}.phar"
cp "${DIST_DIR}/bin/php" "/build/artifacts/php-cli-${OPENEMR_TAG}-freebsd-${ARCH}"
cp "${DIST_DIR}/bin/php-cgi" "/build/artifacts/php-cgi-${OPENEMR_TAG}-freebsd-${ARCH}"
cp "${DIST_DIR}/bin/php-fpm" "/build/artifacts/php-fpm-${OPENEMR_TAG}-freebsd-${ARCH}"

cd /build/artifacts
echo "BUILD FINISHED SUCCESSFULLY"
# Use nohup to ensure the server keeps running even if the telnet session closes
nohup python3 -m http.server 8080 --bind 0.0.0.0 > /tmp/artifact-server.log 2>&1 &
# Wait for the server to be ready
for i in $(seq 1 10); do
    if sockstat -l -p 8080 | grep -q ":8080"; then
        echo "Artifact server is ready on port 8080."
        break
    fi
    sleep 1
done
FREEBUILD

# Step 3: Run build
echo -e "${YELLOW}Step 3/5: Starting QEMU and running build...${NC}"
VM_HTTP_PORT=8888; while lsof -Pi :${VM_HTTP_PORT} -t >/dev/null; do VM_HTTP_PORT=$((VM_HTTP_PORT+1)); done
SERIAL_PORT=4444; while lsof -Pi :${SERIAL_PORT} -t >/dev/null; do SERIAL_PORT=$((SERIAL_PORT+1)); done
HTTP_PORT=8000; while lsof -Pi :${HTTP_PORT} -t >/dev/null; do HTTP_PORT=$((HTTP_PORT+1)); done

cd "${SHARED_DIR}"
python3 -m http.server ${HTTP_PORT} >/dev/null 2>&1 &
HTTP_SERVER_PID=$!
cd - >/dev/null

if [ "${ARCH}" = "arm64" ]; then
    QEMU_CMD="qemu-system-aarch64 -m ${VM_RAM_GB}G -smp ${CPU_CORES} -cpu host -M virt,accel=hvf"
    [ -f "/opt/homebrew/share/qemu/edk2-aarch64-code.fd" ] && QEMU_CMD="${QEMU_CMD} -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd"
else
    QEMU_CMD="qemu-system-x86_64 -m ${VM_RAM_GB}G -smp ${CPU_CORES} -accel hvf"
fi
QEMU_CMD="${QEMU_CMD} -drive if=virtio,file=${FREEBSD_IMAGE},id=hd0 -device virtio-net,netdev=net0 -netdev user,id=net0,hostfwd=tcp::${VM_HTTP_PORT}-:8080 -serial telnet::${SERIAL_PORT},server,nowait -display none"

# Run QEMU and log output
eval "${QEMU_CMD}" > "${TMP_DIR}/qemu.log" 2>&1 &
QEMU_PID=$!

# Wait for QEMU to start and open the serial port
echo "Waiting for VM to start..."
for i in $(seq 1 60); do
    if nc -z localhost ${SERIAL_PORT} >/dev/null 2>&1; then
        echo "VM serial port ready."
        break
    fi
    [ $i -eq 60 ] && echo "Error: VM failed to start or port ${SERIAL_PORT} busy." && exit 1
    sleep 1
done

# Expect automation
cat > "${TMP_DIR}/automate.exp" << EXPECT
set timeout -1
log_user 1
log_file "${TMP_DIR}/expect.log"
match_max 2000000

# Try to connect with retries
set connected 0
for {set i 0} {\$i < 15} {incr i} {
    spawn telnet localhost ${SERIAL_PORT}
    expect {
        "Connected" { set connected 1; break }
        "Connection refused" { sleep 2; continue }
        eof { sleep 2; continue }
        timeout { sleep 2; continue }
    }
}

if {\$connected == 0} {
    puts "Error: Could not connect to VM serial console."
    exit 1
}

# Match the shell prompt more robustly
set prompt "~ # "

expect {
    "login:" { send "root\r"; exp_continue }
    -re \$prompt { send "gpart recover vtbd0; gpart resize -i 3 vtbd0; growfs -y /dev/vtbd0p3\r" }
    timeout { puts "Timeout waiting for login/prompt"; exit 1 }
}

expect -re \$prompt { send "pkg install -y bash curl python3\r" }
expect -re \$prompt { send "fetch -o /tmp/env.sh http://10.0.2.2:${HTTP_PORT}/env.sh\r" }
expect -re \$prompt { send "fetch -o /tmp/build.sh http://10.0.2.2:${HTTP_PORT}/freebsd-build.sh\r" }
expect -re \$prompt { send "bash /tmp/build.sh\r" }

expect {
    "BUILD FINISHED SUCCESSFULLY" { puts "Build successful!"; exp_continue }
    "Artifact server is ready" { puts "Server ready." }
    -re \$prompt { 
        puts "Build failed! Back at prompt."
        send "tail -n 20 /build/*.log\r"
        expect -re \$prompt
        exit 1 
    }
    timeout { puts "Build timed out"; exit 1 }
    eof { 
        # Check if QEMU is still running
        if {[catch {exec ps -p ${QEMU_PID}} msg]} {
            puts "VM process died."
        } else {
            puts "Connection lost but VM is still running."
        }
        exit 1
    }
}
EXPECT

expect "${TMP_DIR}/automate.exp"

# Step 4: Download
echo -e "${YELLOW}Step 4/5: Downloading artifacts...${NC}"
sleep 5 # Give the VM server a moment to settle
DIST_DIR="${SCRIPT_DIR}/dist"
mkdir -p "${DIST_DIR}"
for file in "openemr-${OPENEMR_TAG}-freebsd-${FREEBSD_ARCH}.tar.gz" "openemr-${OPENEMR_TAG}.phar" \
            "php-cli-${OPENEMR_TAG}-freebsd-${FREEBSD_ARCH}" "php-cgi-${OPENEMR_TAG}-freebsd-${FREEBSD_ARCH}" \
            "php-fpm-${OPENEMR_TAG}-freebsd-${FREEBSD_ARCH}"; do
    echo "Downloading ${file}..."
    curl -sf "http://127.0.0.1:${VM_HTTP_PORT}/${file}" -o "${DIST_DIR}/${file}" || echo "Failed to download: ${file}"
    if [ -f "${DIST_DIR}/${file}" ]; then
        chmod +x "${DIST_DIR}/${file}"
        cp "${DIST_DIR}/${file}" "${PROJECT_ROOT}/"
        echo "✓ Copied ${file} to project root."
    fi
done

echo -e "${GREEN}Step 5/5: Build complete! Artifacts in freebsd/dist/ and project root.${NC}"
