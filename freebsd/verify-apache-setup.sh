#!/usr/bin/env bash
# ==============================================================================
# OpenEMR FreeBSD Apache Setup Verification Script
# ==============================================================================
# This script automates the verification of the Apache CGI setup on FreeBSD.
# It boots a QEMU VM, installs Apache, configures it, and runs tests.
#
# Requirements:
#   - macOS (Darwin) with Apple Silicon or Intel
#   - QEMU installed via Homebrew
#   - Build artifacts in freebsd/dist/
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"
DIST_DIR="${SCRIPT_DIR}/dist"
FREEBSD_VERSION="${FREEBSD_VERSION:-15.0}"

# Find a free port for the web server
find_free_port() {
    local port=$1
    while nc -z localhost ${port} 2>/dev/null; do port=$((port + 1)); done
    echo $port
}
HOST_PORT=$(find_free_port 8081)

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}${BOLD}           OpenEMR FreeBSD Apache Verification                            ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check for artifacts
if [ ! -d "${DIST_DIR}" ] || [ -z "$(ls -A "${DIST_DIR}" 2>/dev/null)" ]; then
    echo -e "${RED}ERROR: Build artifacts not found in ${DIST_DIR}${NC}"
    echo "Please run ./freebsd/build-freebsd.sh first."
    exit 1
fi

# Determine architecture
ARCH=$(uname -m)
if [ "${ARCH}" = "arm64" ]; then
    QEMU_SYSTEM_BIN="qemu-system-aarch64"
    FREEBSD_ARCH="aarch64"
    QEMU_MACHINE="virt,accel=hvf"
    UEFI_PATH="/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
    [ ! -f "${UEFI_PATH}" ] && UEFI_PATH="/usr/local/share/qemu/edk2-aarch64-code.fd"
    VM_IMAGE_NAME="FreeBSD-${FREEBSD_VERSION}-RELEASE-arm64-aarch64-ufs.qcow2"
else
    QEMU_SYSTEM_BIN="qemu-system-x86_64"
    FREEBSD_ARCH="amd64"
    QEMU_MACHINE="q35,accel=hvf"
    UEFI_PATH=""
    VM_IMAGE_NAME="FreeBSD-${FREEBSD_VERSION}-RELEASE-amd64-ufs.qcow2"
fi

# VM configuration
VM_DIR="${SCRIPT_DIR}/vm"
mkdir -p "${VM_DIR}"
PID_FILE="${VM_DIR}/qemu-verify.pid"
QEMU_LOG="${VM_DIR}/qemu-verify.log"
# Increase resources for verification
VM_MEM="8G"
VM_CPUS="4"
rm -f "${PID_FILE}" "${QEMU_LOG}"
VM_IMAGE_PATH="${VM_DIR}/${VM_IMAGE_NAME}"
VM_IMAGE_URL="https://download.freebsd.org/releases/VM-IMAGES/${FREEBSD_VERSION}-RELEASE/${FREEBSD_ARCH}/Latest/${VM_IMAGE_NAME}.xz"

echo -e "${YELLOW}Step 1: Setting up VM image...${NC}"
if [ ! -f "${VM_IMAGE_PATH}" ]; then
    echo "Downloading FreeBSD ${FREEBSD_VERSION} image..."
    curl -L --progress-bar -o "${VM_IMAGE_PATH}.xz" "${VM_IMAGE_URL}"
    xz -d "${VM_IMAGE_PATH}.xz"
    qemu-img resize "${VM_IMAGE_PATH}" 20G
    echo "Image ready."
else
    echo "Using existing FreeBSD image: ${VM_IMAGE_PATH}"
fi

# Shared directory for artifacts and materials
SHARED_DIR=$(mktemp -d)
cp "${DIST_DIR}"/* "${SHARED_DIR}/"
mkdir -p "${SHARED_DIR}/apache"
cp "${SCRIPT_DIR}/apache"/* "${SHARED_DIR}/apache/"

# Find the distribution artifact
DIST_ARTIFACT=$(basename $(ls "${DIST_DIR}"/openemr-*.tar.gz | head -n 1))
if [ -z "${DIST_ARTIFACT}" ]; then
    echo -e "${RED}ERROR: Could not find openemr-*.tar.gz in ${DIST_DIR}${NC}"
    exit 1
fi

# Find a free serial port
SERIAL_PORT=4445
while nc -z localhost ${SERIAL_PORT} 2>/dev/null; do SERIAL_PORT=$((SERIAL_PORT + 1)); done

echo -e "${YELLOW}Step 2: Starting QEMU VM...${NC}"
QEMU_ARGS=(
    "${QEMU_SYSTEM_BIN}"
    "-m" "${VM_MEM}"
    "-smp" "${VM_CPUS}"
    "-cpu" "host"
    "-M" "${QEMU_MACHINE}"
    "-drive" "if=virtio,file=${VM_IMAGE_PATH},id=hd0"
    "-device" "virtio-net-pci,netdev=net0"
    "-netdev" "user,id=net0,hostfwd=tcp::${HOST_PORT}-:80"
    "-serial" "telnet::${SERIAL_PORT},server,nowait"
    "-display" "none"
    "-daemonize"
    "-pidfile" "${PID_FILE}"
    "-D" "${QEMU_LOG}"
)
[ -n "${UEFI_PATH}" ] && QEMU_ARGS+=("-bios" "${UEFI_PATH}")

"${QEMU_ARGS[@]}"
sleep 5

if [ -f "${PID_FILE}" ]; then
    QEMU_PID=$(cat "${PID_FILE}")
else
    echo -e "${RED}ERROR: QEMU failed to start (PID file not found)${NC}"
    exit 1
fi

# Start HTTP server for file transfer
HTTP_PORT=$(find_free_port 8002)
cd "${SHARED_DIR}"
python3 -m http.server ${HTTP_PORT} >/dev/null 2>&1 &
HTTP_SERVER_PID=$!
cd - >/dev/null

cleanup() {
    local exit_code=$?
    echo -e "${YELLOW}Cleaning up (exit code: ${exit_code})...${NC}"
    [ -n "${HTTP_SERVER_PID:-}" ] && kill "${HTTP_SERVER_PID}" 2>/dev/null || true
    [ -n "${QEMU_PID:-}" ] && kill -TERM "${QEMU_PID}" 2>/dev/null || true
    [ -d "${SHARED_DIR:-}" ] && rm -rf "${SHARED_DIR}"
}
trap cleanup EXIT INT TERM

echo -e "${YELLOW}Step 3: Configuring Apache inside VM...${NC}"
EXPECT_SCRIPT=$(mktemp)
# Pass variables to expect via environment
export SERIAL_PORT HOST_PORT HTTP_PORT FREEBSD_ARCH DIST_ARTIFACT
cat > "${EXPECT_SCRIPT}" << 'EXPECT_EOF'
set timeout -1
log_user 1
log_file "freebsd/expect-verify.log"
match_max 1000000

set serial_port $env(SERIAL_PORT)
set http_port $env(HTTP_PORT)
set arch $env(FREEBSD_ARCH)
set dist_artifact $env(DIST_ARTIFACT)

# Try to connect with retries
set connected 0
for {set i 0} {$i < 15} {incr i} {
    spawn telnet localhost $serial_port
    expect {
        "Connected" { set connected 1; break }
        "Connection refused" { sleep 2; continue }
        eof { sleep 2; continue }
        timeout { sleep 2; continue }
    }
}

if {$connected == 0} {
    puts "Error: Could not connect to VM serial console."
    exit 1
}

set prompt "root@.*# "

# Helper to send command and wait for prompt
proc send_cmd {cmd} {
    global prompt
    send "$cmd\r"
    expect {
        "Do you want to fetch and install it now? \[y/N\]:" {
            send "y\r"
            exp_continue
        }
        -re $prompt { return }
        eof { puts "\n✗ Connection lost while running: $cmd\n"; exit 1 }
        timeout { puts "\n✗ Timeout while running: $cmd\n"; exit 1 }
    }
}

# Wait for login or prompt
expect {
    "login:" { 
        send "root\r"
        exp_continue 
    }
    -re $prompt { }
    timeout { 
        # Sometimes the prompt is already there but we missed it, try hitting Enter
        send "\r"
        expect {
            -re $prompt { }
            timeout { puts "\n✗ Timeout waiting for login/prompt\n"; exit 1 }
        }
    }
}

send_cmd "export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"
send_cmd "gpart show vtbd0"
send_cmd "gpart recover vtbd0 || true"
send_cmd "gpart resize -i 3 vtbd0 || true"
send_cmd "service growfs onestart"
send_cmd "df -h"
# Fix corrupted pkg database if it exists
send_cmd "rm -rf /var/db/pkg/*.sqlite /var/db/pkg/local.sqlite || true"
send_cmd "env ASSUME_ALWAYS_YES=YES pkg bootstrap -f"
send_cmd "pkg update"
send_cmd "pkg install -y apache24 bash curl libiconv libxml2"
send_cmd "mkdir -p /verify && cd /verify"
send_cmd "fetch -o artifacts.tar.gz http://10.0.2.2:$http_port/$dist_artifact"
send_cmd "tar -xzf artifacts.tar.gz"
send_cmd "mv openemr-*-freebsd-*/* ."
send_cmd "cp bin/php php-cli-v7_0_4-freebsd-$arch"
send_cmd "cp bin/php-cgi php-cgi-v7_0_4-freebsd-$arch"
send_cmd "chmod +x php-*-freebsd-*"
send_cmd "export LD_LIBRARY_PATH=/verify/lib:/usr/local/lib"
send_cmd "mkdir -p apache"
send_cmd "for f in benchmark.sh extract-openemr.sh httpd-openemr.conf php-wrapper.sh README.md setup-apache-config.sh test-cgi-setup.sh; do fetch -o apache/\$f http://10.0.2.2:$http_port/apache/\$f; done"
send_cmd "chmod +x apache/*.sh"
send_cmd "sed -i '' '1s|^|set -x\\n|' apache/*.sh"
send_cmd "echo 'y' | LD_LIBRARY_PATH=/verify/lib:/usr/local/lib bash apache/extract-openemr.sh /verify/openemr-extracted"
send_cmd "LD_LIBRARY_PATH=/verify/lib:/usr/local/lib bash apache/setup-apache-config.sh"
send_cmd "sysrc apache24_enable=YES && service apache24 restart"
send_cmd "LD_LIBRARY_PATH=/verify/lib:/usr/local/lib bash apache/test-cgi-setup.sh"
send_cmd "echo VERIFICATION_COMPLETE"

expect {
    "VERIFICATION_COMPLETE" { puts "\n✓ Apache verification complete!\n" }
    timeout { puts "\n✗ Verification timed out final\n"; exit 1 }
    eof { puts "\n✗ Connection lost final\n"; exit 1 }
}
EXPECT_EOF

expect "${EXPECT_SCRIPT}"

echo ""
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}✓ Verification Successful!${NC}"
echo -e "${GREEN}OpenEMR is running via Apache CGI inside the VM.${NC}"
echo -e "${GREEN}You can manually verify at: http://localhost:${HOST_PORT}${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "Press Enter to shut down the VM and clean up..."
read

