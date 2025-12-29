# Dockerfile for OpenEMR Static Binary
# Uses debian:bookworm-slim for minimal size with glibc compatibility
# Note: The static binary is built on Ubuntu (glibc), so we need a glibc-based image.
# We use debian:bookworm-slim instead of scratch because we need a shell for the entrypoint.
# For a truly scratch image, we'd need to compile the entrypoint as a static binary.

FROM debian:bookworm-slim

# Copy the static binary, PHP CLI, PHP FPM, and PHAR
COPY openemr-*-linux-amd64 /usr/local/bin/openemr
COPY php-cli-*-linux-amd64 /usr/local/bin/php
COPY php-fpm-*-linux-amd64 /usr/local/bin/php-fpm
COPY openemr-*.phar /usr/local/share/openemr.phar

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Create non-root user and set up directories
RUN useradd -r -s /bin/sh -u 1000 openemr && \
    mkdir -p /app /app/openemr-extracted && \
    chown -R openemr:openemr /app /usr/local/bin/openemr /usr/local/bin/php /usr/local/share/openemr.phar

# Set working directory
WORKDIR /app

# Install gosu for user switching
RUN apt-get update && \
    apt-get install -y --no-install-recommends gosu && \
    rm -rf /var/lib/apt/lists/*

# Create entrypoint wrapper that fixes permissions and switches user
COPY docker-entrypoint-wrapper.sh /usr/local/bin/docker-entrypoint-wrapper.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-wrapper.sh

# Keep as root for entrypoint wrapper to fix permissions
# USER openemr

# Expose default port
EXPOSE 8080

# Use entrypoint wrapper that fixes permissions
# Note: We run as root initially to fix volume permissions, then switch to openemr user
ENTRYPOINT ["/usr/local/bin/docker-entrypoint-wrapper.sh"]
