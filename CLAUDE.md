# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Production-focused Moodle LMS deployment using Docker with Alpine Linux. Security-hardened, non-root execution, modular service architecture.

## Architecture

**Services (docker-compose.yml):**
- **moodle**: PHP 8.3-FPM Alpine - Application server, runs as `moodle` user (UID 1000)
- **nginx**: Reverse proxy with HTTPS, security headers, rate limiting
- **mysql**: Database (dev/test only - production uses external DB)
- **redis**: Session cache (256MB, LRU eviction)

**Network:** Custom bridge 172.20.0.0/16

**Volumes:** moodledata, moodle-www, mysql-data, redis-data

## Directory Structure

```
config/           # PHP and server configuration
  opcache.ini         # OPcache settings (256MB, JIT enabled)
  php-fpm-security.conf   # FPM pool security (dynamic workers, IP whitelist)
  php-moodle.ini      # Moodle-specific PHP settings
  php-security.ini    # Core PHP hardening (disabled dangerous functions)
scripts/          # Runtime scripts
  docker-entrypoint.sh    # Startup: validation, DB wait, config.php generation
  healthcheck.sh      # FastCGI ping for container health
nginx/            # Nginx configuration
  moodle.conf         # Server blocks, SSL, FastCGI upstream
  security-headers.conf   # HSTS, CSP, X-Frame-Options
```

## Commands

**Build and Run:**
```bash
cp .env.example .env
# Edit .env with credentials
docker-compose build
docker-compose up -d
```

**Build with specific Moodle/PHP version:**
```bash
docker-compose build --build-arg MOODLE_VERSION=405 --build-arg PHP_VERSION=8.3
```

**View logs:**
```bash
docker-compose logs -f moodle
docker-compose logs -f nginx
```

**Restart services:**
```bash
docker-compose restart moodle
docker-compose restart nginx
```

**Shell into container:**
```bash
docker-compose exec moodle sh
```

## Configuration

**Required Environment Variables (.env):**
- `MOODLE_WWWROOT` - Full URL (https://moodle.example.com)
- `MOODLE_DB_HOST` - Database server address
- `MOODLE_DB_PASSWORD` - Database password
- `MOODLE_PASSWORD_SALT` - Auto-generated if missing

**Optional:**
- `MOODLE_SSL_PROXY=true` - When behind reverse proxy with SSL termination
- `MOODLE_DEBUG=true` - Debug mode (never in production)
- `REDIS_PASSWORD` - For Redis session cache

## Security Constraints

- All containers run as non-root users
- PHP dangerous functions disabled: exec, shell_exec, system, passthru, proc_open, popen
- `open_basedir` restricts PHP to: /var/www/html, /var/moodledata, /tmp, /usr/share/zoneinfo
- Session cookies: HTTPOnly, Secure, SameSite=Lax
- TLS 1.2+ only, modern ciphers
- HSTS enabled with preload

## Database Notes

The mysql service in docker-compose.yml is for development only. Production deployments should:
1. Use an external MySQL/MariaDB server
2. Set `MOODLE_DB_HOST` to the external server address
3. Remove or comment out the mysql service

## Entrypoint Behavior

`scripts/docker-entrypoint.sh` performs on startup:
1. Validates required environment variables
2. Checks non-root execution
3. Waits for database availability (30 attempts, 2s intervals)
4. Generates `/var/www/html/config.php` dynamically
5. Creates moodledata subdirectories with proper permissions

## Build Environment Notes

**FortiGate SSL Inspection:** The Docker daemon is configured with an HTTPS proxy at `10.71.48.17:8080` that performs SSL inspection. The `config/fortigate_proxy.crt` file contains the CA certificate required for Alpine containers to trust HTTPS connections during build. If builds fail with "TLS: server certificate not trusted", verify this certificate is current.

**PHP 8.x Compatibility:** The `xmlrpc` extension is not available in PHP 8.0+ (removed, was deprecated in 7.4). Moodle 4.x does not require it.
