#!/bin/sh
# Docker entrypoint wrapper that fixes volume permissions and switches to non-root user

set -e

# Fix permissions on volume mount - ensure it exists and is writable
mkdir -p /app/openemr-extracted
chown -R openemr:openemr /app/openemr-extracted
chmod -R 755 /app/openemr-extracted

# Ensure /app directory itself is writable
chown -R openemr:openemr /app
chmod 755 /app

# Switch to non-root user and run the actual entrypoint
exec gosu openemr /usr/local/bin/docker-entrypoint.sh "$@"

