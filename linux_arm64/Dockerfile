# Dockerfile for OpenEMR Static Binary
# Uses debian:bookworm-slim for minimal size with glibc compatibility
# Note: The static binary is built on Ubuntu (glibc), so we need a glibc-based image.
# We use debian:bookworm-slim instead of scratch because we need a shell for the entrypoint.
# For a truly scratch image, we'd need to compile the entrypoint as a static binary.

FROM debian:bookworm-slim

# Install gosu for easy step-down from root
RUN apt-get update && \
    apt-get install -y --no-install-recommends gosu && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd -r -s /bin/sh -u 1000 openemr && \
    mkdir -p /app /app/openemr-extracted && \
    chown -R openemr:openemr /app

# Copy the static binary, PHP CLI, and PHAR
COPY openemr-*-linux-arm64 /usr/local/bin/openemr
COPY php-cli-*-linux-arm64 /usr/local/bin/php
COPY openemr-*.phar /usr/local/share/openemr.phar

# Copy entrypoint scripts
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY docker-entrypoint-wrapper.sh /usr/local/bin/docker-entrypoint-wrapper.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint-wrapper.sh

# Set working directory
WORKDIR /app

# Expose default port
EXPOSE 8080

# Use the wrapper script as the entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint-wrapper.sh"]

