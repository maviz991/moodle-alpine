#!/bin/bash
# ==============================================================================
# Health Check Script para Moodle Container
# ==============================================================================

set -e

# Verifica se PHP-FPM está respondendo
SCRIPT_NAME=/php-fpm-ping \
SCRIPT_FILENAME=/php-fpm-ping \
REQUEST_METHOD=GET \
cgi-fcgi -bind -connect 127.0.0.1:9000 2>/dev/null | grep -q "pong"

exit $?
