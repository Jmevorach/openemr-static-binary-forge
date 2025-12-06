#!/bin/sh
# Docker entrypoint wrapper that fixes volume permissions and switches to non-root user

set -e

# Ensure directories exist and fix permissions on volume mount
# The volume is mounted at /app/openemr-extracted
# The user 'openemr' needs to be able to write to it.
# This script runs as root, so it can change ownership.
mkdir -p /app/openemr-extracted
chown -R openemr:openemr /app/openemr-extracted
chmod -R 755 /app/openemr-extracted

# Ensure /app is also writable by the openemr user
chown -R openemr:openemr /app

# Switch to non-root user and run the actual entrypoint
exec gosu openemr /usr/local/bin/docker-entrypoint.sh "$@"

