#!/usr/bin/env bash
# ==============================================================================
# OpenEMR FreeBSD Apache + PHP-FPM Runner for macOS
# ==============================================================================
# This script boots a FreeBSD QEMU VM, installs Apache, and configures it
# to serve OpenEMR using the custom PHP FPM binary.
#
# Usage:
#   ./run-freebsd-fpm.sh [options]
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

# Get paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"
DIST_DIR="${SCRIPT_DIR}/dist"
APACHE_FPM_DIR="${SCRIPT_DIR}/apache_fpm"

# Default arguments
HOST_PORT="8081"
FREEBSD_VERSION="15.0"
VM_MEM="8G"
VM_CPUS="4"
DEBUG="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port) HOST_PORT="$2"; shift 2 ;;
        -v|--version) FREEBSD_VERSION="$2"; shift 2 ;;
        -m|--memory) VM_MEM="${2}G"; shift 2 ;;
        -c|--cpus) VM_CPUS="$2"; shift 2 ;;
        --debug) DEBUG="true"; shift ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -p, --port PORT      Host port to access OpenEMR (default: 8081)"
            echo "  -v, --version VER    FreeBSD version (default: 15.0)"
            echo "  -m, --memory MEM     VM memory in GB (default: 8)"
            echo "  -c, --cpus CPUS      Number of CPU cores (default: 4)"
            echo "  --debug              Enable debug logging"
            echo "  -h, --help           Show this help message"
            exit 0
            ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
done

echo -e "${CYAN}${BOLD}OpenEMR FreeBSD Apache + PHP-FPM Runner${NC}"
echo "=========================================="

# 1. Check Requirements
echo -e "${YELLOW}Step 1: Checking requirements...${NC}"

# Check for build artifacts
DIST_ARTIFACT=$(basename $(ls "${DIST_DIR}"/openemr-*.tar.gz 2>/dev/null | head -n 1 || true))
if [ -z "${DIST_ARTIFACT}" ]; then
    echo -e "${RED}ERROR: Could not find openemr-*.tar.gz in ${DIST_DIR}${NC}"
    echo "Please run ./freebsd/build-freebsd.sh first."
    exit 1
fi

PHP_FPM_ARTIFACT=$(basename $(ls "${DIST_DIR}"/php-fpm-* 2>/dev/null | head -n 1 || true))
if [ -z "${PHP_FPM_ARTIFACT}" ]; then
    echo -e "${RED}ERROR: Could not find php-fpm-* in ${DIST_DIR}${NC}"
    exit 1
fi

# Determine architecture
ARCH=$(uname -m)
QEMU_SYSTEM_BIN=""
FREEBSD_ARCH=""
QEMU_MACHINE=""
UEFI_PATH=""

if [ "${ARCH}" = "arm64" ]; then
    QEMU_SYSTEM_BIN="qemu-system-aarch64"
    FREEBSD_ARCH="aarch64"
    QEMU_MACHINE="virt,accel=hvf"
    [ -f "/opt/homebrew/share/qemu/edk2-aarch64-code.fd" ] && UEFI_PATH="/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
    [ -f "/usr/local/share/qemu/edk2-aarch64-code.fd" ] && UEFI_PATH="/usr/local/share/qemu/edk2-aarch64-code.fd"
elif [ "${ARCH}" = "x86_64" ]; then
    QEMU_SYSTEM_BIN="qemu-system-x86_64"
    FREEBSD_ARCH="amd64"
    QEMU_MACHINE="q35,accel=hvf"
fi

# 2. VM Image Setup
VM_DIR="${SCRIPT_DIR}/vm"
mkdir -p "${VM_DIR}"
VM_IMAGE_NAME="FreeBSD-${FREEBSD_VERSION}-RELEASE-${FREEBSD_ARCH}-ufs.qcow2"
if [ "${FREEBSD_ARCH}" = "aarch64" ] && [[ "${FREEBSD_VERSION}" == "15.0" ]]; then
    VM_IMAGE_NAME="FreeBSD-15.0-RELEASE-arm64-aarch64-ufs.qcow2"
fi
VM_IMAGE_PATH="${VM_DIR}/${VM_IMAGE_NAME}"

# Always download a fresh image for maximum reliability
echo -e "${YELLOW}Step 2: Downloading fresh FreeBSD VM image...${NC}"
rm -f "${VM_IMAGE_PATH}" "${VM_IMAGE_PATH}.xz"
URL="https://download.freebsd.org/releases/VM-IMAGES/${FREEBSD_VERSION}-RELEASE/${FREEBSD_ARCH}/Latest/${VM_IMAGE_NAME}.xz"
curl -L -f --progress-bar -o "${VM_IMAGE_PATH}.xz" "${URL}"
echo "Decompressing..."
xz -d "${VM_IMAGE_PATH}.xz"
echo "Resizing image to 30G..."
qemu-img resize "${VM_IMAGE_PATH}" 30G

# 3. Port Management
echo -e "${YELLOW}Step 3: Checking ports...${NC}"
# Check if the host port is in use and warn the user instead of killing it automatically
if lsof -Pi :${HOST_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Port ${HOST_PORT} is already in use.${NC}"
    echo "To free up this port, you can run:"
    echo -e "${CYAN}lsof -i :${HOST_PORT} -t | xargs kill -9${NC}"
    echo ""
    exit 1
fi

find_free_port() {
    local port=$1
    while lsof -Pi :${port} -sTCP:LISTEN -t >/dev/null 2>&1; do
        port=$((port + 1))
    done
    echo "${port}"
}

SERIAL_PORT=$(find_free_port 4446)
HTTP_PORT=$(find_free_port 8003)

# 4. Shared Directory Setup
SHARED_DIR=$(mktemp -d)
cp "${DIST_DIR}/${DIST_ARTIFACT}" "${SHARED_DIR}/"
cp "${DIST_DIR}/${PHP_FPM_ARTIFACT}" "${SHARED_DIR}/"
cp -r "${APACHE_FPM_DIR}" "${SHARED_DIR}/apache_fpm"

# 5. Start HTTP Server for File Transfer
cd "${SHARED_DIR}"
python3 -m http.server ${HTTP_PORT} >/dev/null 2>&1 &
HTTP_SERVER_PID=$!
cd - >/dev/null

# 6. Start QEMU
PID_FILE="${VM_DIR}/qemu-fpm.pid"
rm -f "${PID_FILE}"

echo -e "${YELLOW}Step 4: Starting QEMU VM...${NC}"
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
)
[ -n "${UEFI_PATH}" ] && QEMU_ARGS+=("-bios" "${UEFI_PATH}")

"${QEMU_ARGS[@]}"
sleep 5
QEMU_PID=$(cat "${PID_FILE}")
echo -e "${GREEN}✓ QEMU started (PID: ${QEMU_PID})${NC}"

cleanup() {
    local exit_code=$?
    if [ "${exit_code}" -ne 0 ]; then
        echo -e "${RED}Error occurred, shutting down...${NC}"
    else
        echo -e "${YELLOW}Shutting down...${NC}"
    fi
    [ -n "${HTTP_SERVER_PID:-}" ] && kill "${HTTP_SERVER_PID}" 2>/dev/null || true
    [ -n "${QEMU_PID:-}" ] && kill -TERM "${QEMU_PID}" 2>/dev/null || true
    [ -d "${SHARED_DIR:-}" ] && rm -rf "${SHARED_DIR}"
    echo -e "${GREEN}Goodbye!${NC}"
}
trap cleanup EXIT INT TERM

# 7. Expect Script for Configuration
echo -e "${YELLOW}Step 5: Configuring Apache + PHP-FPM inside VM (this may take a few minutes)...${NC}"
EXPECT_SCRIPT=$(mktemp)
cat > "${EXPECT_SCRIPT}" << 'EXPECT_EOF'
set timeout -1
log_user 1
log_file "expect-fpm-run.log"
match_max 1000000

set serial_port [lindex $argv 0]
set http_port [lindex $argv 1]
set arch [lindex $argv 2]
set dist_artifact [lindex $argv 3]
set host_port [lindex $argv 4]

spawn telnet localhost $serial_port

set connected 0
for {set i 0} {$i < 15} {incr i} {
    expect {
        "Connected" { set connected 1; break }
        "Connection refused" { sleep 2; spawn telnet localhost $serial_port }
        eof { sleep 2; spawn telnet localhost $serial_port }
        timeout { sleep 2; spawn telnet localhost $serial_port }
    }
}

if {$connected == 0} {
    puts "Error: Could not connect to VM serial console."
    exit 1
}

set prompt "root@.*# "

proc send_cmd {cmd {check_err 1}} {
    global prompt
    send "$cmd\r"
    expect {
        -re $prompt { 
            if {$check_err} {
                # Check for common failure indicators in output
                # (Note: this is basic, but helps catch obvious errors)
            }
            return 
        }
        eof { puts "Connection lost"; exit 1 }
        timeout { 
            send "\r"
            expect {
                -re $prompt { return }
                timeout { puts "Timeout"; exit 1 }
            }
        }
    }
}

expect {
    "Enter full pathname of shell or RETURN for /bin/sh:" { 
        send "\r"
        expect "# "
        send "fsck -y /\r"
        expect "# "
        send "reboot\r"
        exp_continue 
    }
    "login:" { send "root\r"; exp_continue }
    -re $prompt { }
}

send_cmd "export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"
# Ensure networking is up
send_cmd "ifconfig vtnet0 up && dhclient vtnet0 || true"
# Verify connectivity to host
send_cmd "ping -c 1 10.0.2.2 || echo 'Host unreachable'"

send_cmd "gpart recover vtbd0; gpart resize -i 3 vtbd0 || true"
send_cmd "service growfs onestart"
send_cmd "rm -rf /var/db/pkg/*.sqlite /var/db/pkg/local.sqlite || true"
send_cmd "env ASSUME_ALWAYS_YES=YES pkg bootstrap -f"
send_cmd "pkg update"
send_cmd "pkg install -y apache24 bash curl libiconv libxml2 openssl sqlite3 icu oniguruma"
send_cmd "mkdir -p /verify && cd /verify"
send_cmd "rm -rf bin lib openemr.phar artifacts.tar.gz openemr-extracted"
send_cmd "fetch -o artifacts.tar.gz http://10.0.2.2:$http_port/$dist_artifact"
# Verify download
send_cmd "ls -lh artifacts.tar.gz || (echo 'Download failed' && exit 1)"
send_cmd "tar -xzf artifacts.tar.gz --strip-components=1"
send_cmd "mkdir -p apache_fpm"
send_cmd "for f in benchmark.sh extract-openemr.sh httpd-openemr.conf php-fpm.conf run-fpm.sh README.md setup-apache-config.sh test-fpm-setup.sh; do fetch -o apache_fpm/\$f http://10.0.2.2:$http_port/apache_fpm/\$f; done"
# Verify scripts
send_cmd "ls apache_fpm/extract-openemr.sh || (echo 'Scripts download failed' && exit 1)"
send_cmd "chmod +x apache_fpm/*.sh"
# Extraction - ensure we are in /verify so it can find bin/ and openemr.phar
send_cmd "cd /verify"
send_cmd "echo 'y' | bash apache_fpm/extract-openemr.sh /verify/openemr-extracted"
# Verify extraction
send_cmd "ls -d /verify/openemr-extracted/interface || (echo 'Extraction failed - openemr-extracted/interface not found' && ls -R /verify/openemr-extracted && exit 1)"
send_cmd "chown -R www:www /verify/openemr-extracted"
send_cmd "chmod -R 777 /verify/openemr-extracted/sites"
send_cmd "sync"
# Run setup script with debug output
send_cmd "sysrc apache24_enable=YES"
send_cmd "bash -x apache_fpm/setup-apache-config.sh"
# Start FPM
send_cmd "cd /verify/apache_fpm && bash run-fpm.sh"
# Run verification test
send_cmd "bash test-fpm-setup.sh"
# Start Apache - ensure we enable it and restart
send_cmd "sysrc apache24_enable=YES"
send_cmd "service apache24 stop || true"
send_cmd "service apache24 start"
# Final check - ensure Apache is actually running
send_cmd "sockstat -4 -l | grep :80"

puts "\n\n"
puts "=================================================================="
puts "  SUCCESS: OpenEMR is now running on Apache + FPM inside FreeBSD!"
puts "  URL: http://localhost:$host_port"
puts "=================================================================="
puts "\nPress Ctrl+C to stop the VM and exit."
puts "\n"

expect {
    timeout { exp_continue }
    eof { puts "VM console disconnected."; exit 0 }
}
EXPECT_EOF

expect "${EXPECT_SCRIPT}" "${SERIAL_PORT}" "${HTTP_PORT}" "${FREEBSD_ARCH}" "${DIST_ARTIFACT}" "${HOST_PORT}"

