#!/bin/sh
# OpenEMR Apache CGI Benchmark Script for Linux (amd64)
# Uses Apache Benchmark (ab) to test performance

set -e

# Configuration
URL="${1:-http://localhost/test.php}"
CONCURRENCY="${2:-10}"
REQUESTS="${3:-100}"

echo "============================================================================"
echo "OpenEMR Apache CGI Benchmark (Linux amd64)"
echo "============================================================================"
echo "URL:         $URL"
echo "Concurrency: $CONCURRENCY"
echo "Requests:    $REQUESTS"
echo "============================================================================"
echo ""

if ! command -v ab >/dev/null 2>&1; then
    echo "Error: Apache Benchmark (ab) not found."
    echo "Install it via apt: sudo apt install apache2-utils"
    exit 1
fi

echo "Running benchmark..."
ab -c "$CONCURRENCY" -n "$REQUESTS" "$URL"
