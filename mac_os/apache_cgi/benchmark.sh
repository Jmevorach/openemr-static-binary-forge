#!/bin/bash
# OpenEMR Apache CGI Benchmark Script
# Uses Apache Benchmark (ab) to test performance

set -e

# Configuration
URL="${1:-http://localhost:8080/test.php}"
CONCURRENCY="${2:-10}"
REQUESTS="${3:-100}"

echo "============================================================================"
echo "OpenEMR Apache CGI Benchmark"
echo "============================================================================"
echo "URL:         $URL"
echo "Concurrency: $CONCURRENCY"
echo "Requests:    $REQUESTS"
echo "============================================================================"
echo ""

if ! command -v ab >/dev/null 2>&1; then
    echo "Error: Apache Benchmark (ab) not found."
    echo "Install it via Homebrew: brew install httpd (it comes with httpd)"
    exit 1
fi

echo "Running benchmark..."
ab -c "$CONCURRENCY" -n "$REQUESTS" "$URL"

