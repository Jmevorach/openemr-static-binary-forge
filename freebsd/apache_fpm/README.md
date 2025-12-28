# Apache Setup for OpenEMR on FreeBSD (PHP-FPM)

This directory contains configuration files and scripts for running OpenEMR locally with Apache HTTP Server on FreeBSD using the static PHP FPM binary.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
  - [1. Extract OpenEMR PHAR](#1-extract-openemr-phar)
  - [2. Configure Apache](#2-configure-apache)
  - [3. Start PHP-FPM](#3-start-php-fpm)
  - [4. Start Apache](#4-start-apache)
  - [5. Access OpenEMR](#5-access-openemr)
- [Configuration Files](#configuration-files)
- [Troubleshooting](#troubleshooting)

## Overview

This setup demonstrates running OpenEMR using:
- **Apache HTTP Server** - Web server for serving static files
- **PHP-FPM** - FastCGI Process Manager for executing PHP
- **Static PHP FPM binary** - Uses the `php-fpm-*-freebsd-*` binary built by the FreeBSD build script

Using PHP-FPM is generally faster and more robust than CGI for production-like environments.

<div align="center">

<img src="../../images/freebsd_apache_fpm_openemr_setup_output.png" alt="OpenEMR Setup Page via Apache on FreeBSD" width="600">

*Success: OpenEMR Setup Tool running on Apache HTTP Server inside FreeBSD*

</div>

## Project Structure

```
freebsd/apache_fpm/
├── httpd-openemr.conf        # Apache virtual host configuration template
├── php-fpm.conf              # PHP-FPM configuration
├── run-fpm.sh                # Script to start PHP-FPM
├── extract-openemr.sh        # Helper script to extract PHAR
├── setup-apache-config.sh    # Automated Apache configuration script
├── test-fpm-setup.sh         # Component test script
└── README.md                 # This file (Apache FPM setup instructions)
```

## Prerequisites

1. **FreeBSD** - This example is designed for FreeBSD
2. **Apache HTTP Server** - Install via pkg:
   ```bash
   pkg install apache24
   ```
3. **Built OpenEMR Binaries** - Run the build script first:
   ```bash
   cd ..
   ./build-freebsd.sh
   ```
   This creates artifacts in the `dist/` directory:
   - `php-cli-*-freebsd-*` - PHP CLI binary (for PHAR extraction)
   - `php-fpm-*-freebsd-*` - PHP FPM binary (used for execution)
   - `openemr-*.phar` - OpenEMR PHAR archive

## Setup

### 1. Extract OpenEMR PHAR

First, extract the OpenEMR PHAR archive:

```bash
cd freebsd/apache_fpm
./extract-openemr.sh
```

### 2. Configure Apache

Run the setup script to automatically configure Apache:

```bash
cd freebsd/apache_fpm
sudo ./setup-apache-config.sh
```

This script will:
- Copy and configure `httpd-openemr.conf` to `/usr/local/etc/apache24/Includes/`
- Enable required Apache modules (including `mod_proxy_fcgi`)
- Validate the configuration syntax

### 3. Start PHP-FPM

Start the PHP-FPM process:

```bash
./run-fpm.sh
```

This will start PHP-FPM in the background listening on `127.0.0.1:9000`.

### 4. Start Apache

```bash
# Enable and start Apache
sysrc apache24_enable="YES"
service apache24 start

# Or restart if already running
service apache24 restart
```

### 5. Verify the Setup

You can test the components individually using the test script:

```bash
./test-fpm-setup.sh
```

### 6. Access OpenEMR

OpenEMR should now be accessible at:
- `http://localhost/`

## Configuration Files

### httpd-openemr.conf

Apache virtual host configuration that proxies `.php` requests to the FPM socket.

### php-fpm.conf

Configuration for the PHP-FPM process manager, defining worker pools and listening sockets.

### run-fpm.sh

Helper script that finds the static PHP FPM binary and starts it with the correct configuration.

## Troubleshooting

### PHP-FPM not starting

- Check for existing processes: `ps aux | grep php-fpm`
- Check the error log: `tail -f /tmp/php-fpm.error.log`
- Ensure no other service is using port 9000: `sockstat -l -p 9000`

### Apache "Service Unavailable" (503)

- This usually means Apache cannot connect to PHP-FPM.
- Verify PHP-FPM is running: `ps aux | grep php-fpm`
- Check if port 9000 is open: `sockstat -l -p 9000`

### Permission errors

- Ensure the user specified in `php-fpm.conf` has access to the OpenEMR files.
- The default is `www` which is the standard Apache user on FreeBSD.
