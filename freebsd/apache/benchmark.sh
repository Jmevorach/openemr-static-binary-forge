#!/bin/sh
# OpenEMR Apache CGI Benchmark Script for FreeBSD
# Uses Apache Benchmark (ab) to test performance

set -e

# Configuration
URL="${1:-http://localhost/test.php}"
CONCURRENCY="${2:-10}"
REQUESTS="${3:-100}"

echo "============================================================================"
echo "OpenEMR Apache CGI Benchmark (FreeBSD)"
echo "============================================================================"
echo "URL:         $URL"
echo "Concurrency: $CONCURRENCY"
echo "Requests:    $REQUESTS"
echo "============================================================================"
echo ""

if ! command -v ab >/dev/null 2>&1; then
    echo "Error: Apache Benchmark (ab) not found."
    echo "Install it via pkg: pkg install apache24"
    exit 1
fi

echo "Running benchmark..."
ab -c "$CONCURRENCY" -n "$REQUESTS" "$URL"
