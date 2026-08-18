#!/bin/bash
# ==============================================================================
# Docker Entrypoint para Moodle Seguro
# ==============================================================================
set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==============================================================================
# VARIÁVEIS DE AMBIENTE OBRIGATÓRIAS
# ==============================================================================
REQUIRED_VARS=(
    "MOODLE_DB_TYPE"
    "MOODLE_DB_HOST"
    "MOODLE_DB_NAME"
    "MOODLE_DB_USER"
    "MOODLE_DB_PASSWORD"
    "MOODLE_WWWROOT"
)

# Variáveis opcionais com valores padrão
: "${MOODLE_DB_PORT:=3306}"
: "${MOODLE_DB_PREFIX:=mdl_}"
: "${MOODLE_DATA_DIR:=/var/moodledata}"
: "${MOODLE_SKIP_INSTALL:=false}"
: "${MOODLE_DEBUG:=false}"
: "${MOODLE_SSL_PROXY:=false}"

# ==============================================================================
# VERIFICAÇÃO DE VARIÁVEIS OBRIGATÓRIAS
# ==============================================================================
check_required_vars() {
    log_info "Verificando variáveis de ambiente obrigatórias..."
    local missing=0
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "Variável obrigatória não definida: $var"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        log_error "Abortando devido a variáveis faltando."
        exit 1
    fi
    
    log_info "Todas as variáveis obrigatórias estão definidas."
}

# ==============================================================================
# VALIDAÇÃO DE SEGURANÇA
# ==============================================================================
security_checks() {
    log_info "Executando verificações de segurança..."
    
    # Verifica se não está rodando como root
    if [ "$(id -u)" = "0" ]; then
        log_warn "Container iniciado como root. Isso não é recomendado em produção!"
    fi
    
    # Verifica permissões do moodledata
    if [ -d "$MOODLE_DATA_DIR" ]; then
        local perms=$(stat -c %a "$MOODLE_DATA_DIR")
        if [ "$perms" != "770" ] && [ "$perms" != "750" ]; then
            log_warn "Permissões de $MOODLE_DATA_DIR são $perms (recomendado: 770)"
        fi
    fi
    
    # Verifica se o password não está em texto claro no ambiente
    if [ -n "$MOODLE_DB_PASSWORD" ] && [ ${#MOODLE_DB_PASSWORD} -lt 12 ]; then
        log_warn "Senha do banco de dados parece fraca (< 12 caracteres)"
    fi
    
    log_info "Verificações de segurança concluídas."
}

# ==============================================================================
# AGUARDA BANCO DE DADOS
# ==============================================================================
wait_for_database() {
    log_info "Aguardando conexão com o banco de dados ($MOODLE_DB_HOST:$MOODLE_DB_PORT)..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if php -r "
            \$conn = @new mysqli('$MOODLE_DB_HOST', '$MOODLE_DB_USER', '$MOODLE_DB_PASSWORD', '', $MOODLE_DB_PORT);
            if (\$conn->connect_error) { exit(1); }
            \$conn->close();
            exit(0);
        " 2>/dev/null; then
            log_info "Conexão com banco de dados estabelecida!"
            return 0
        fi
        
        log_warn "Tentativa $attempt/$max_attempts - Banco não disponível, aguardando..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log_error "Não foi possível conectar ao banco de dados após $max_attempts tentativas"
    exit 1
}

# ==============================================================================
# CONFIGURAÇÃO DO MOODLE (config.php)
# ==============================================================================
configure_moodle() {
    local config_file="${MOODLE_DIR:-/var/www/html}/config.php"
    
    # Se config.php já existe e MOODLE_SKIP_INSTALL=true, não sobrescreve
    if [ -f "$config_file" ] && [ "$MOODLE_SKIP_INSTALL" = "true" ]; then
        log_info "config.php já existe e MOODLE_SKIP_INSTALL=true. Mantendo configuração existente."
        return 0
    fi

    # config.php é protegido com chmod 440 no final desta função; sem isso,
    # qualquer restart do container (não só rebuild) falha com "Permission denied"
    # ao tentar regenerar o arquivo.
    if [ -f "$config_file" ]; then
        chmod u+w "$config_file"
    fi

    log_info "Gerando config.php seguro..."
    
    # Gera salt seguro se não fornecido
    : "${MOODLE_PASSWORD_SALT:=$(openssl rand -hex 32)}"
    
    # Debug settings
    local debug_display="false"
    local debug_level="0"
    if [ "$MOODLE_DEBUG" = "true" ]; then
        debug_display="true"
        debug_level="32767"
        log_warn "Modo DEBUG habilitado - NÃO USE EM PRODUÇÃO!"
    fi
    
    # SSL Proxy settings
    local ssl_proxy_setting=""
    local cookiesecure_value="false"
    if [ "$MOODLE_SSL_PROXY" = "true" ]; then
        ssl_proxy_setting='$CFG->sslproxy = true;'
        cookiesecure_value="true"
    fi
    
    cat > "$config_file" << EOFCONFIG
<?php
// ==============================================================================
// Moodle Configuration - Gerado automaticamente
// ATENÇÃO: Este arquivo contém informações sensíveis!
// ==============================================================================

unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

// ==============================================================================
// CONFIGURAÇÃO DO BANCO DE DADOS
// ==============================================================================
\$CFG->dbtype    = '${MOODLE_DB_TYPE}';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = '${MOODLE_DB_HOST}';
\$CFG->dbname    = '${MOODLE_DB_NAME}';
\$CFG->dbuser    = '${MOODLE_DB_USER}';
\$CFG->dbpass    = '${MOODLE_DB_PASSWORD}';
\$CFG->prefix    = '${MOODLE_DB_PREFIX}';

// Opções de conexão segura
\$CFG->dboptions = array(
    'dbpersist' => false,
    'dbsocket'  => '',
    'dbport'    => '${MOODLE_DB_PORT}',
    'dbcollation' => 'utf8mb4_unicode_ci',
);

// ==============================================================================
// DIRETÓRIOS E URLs
// ==============================================================================
\$CFG->wwwroot   = '${MOODLE_WWWROOT}';
\$CFG->dataroot  = '${MOODLE_DATA_DIR}';
\$CFG->directorypermissions = 02770;

// Admin directory (pode ser renomeado por segurança)
\$CFG->admin = 'admin';

// ==============================================================================
// CONFIGURAÇÕES DE SEGURANÇA
// ==============================================================================
// Salt para hashes de senha
\$CFG->passwordsaltmain = '${MOODLE_PASSWORD_SALT}';

// Força HTTPS
\$CFG->loginhttps = false; // Deprecated, use \$CFG->wwwroot com https://

// SSL Proxy (se atrás de load balancer/reverse proxy)
${ssl_proxy_setting}

// Headers de segurança
\$CFG->cookiesecure = ${cookiesecure_value};
\$CFG->cookiehttponly = true;

// Desabilita CLI installer pela web
\$CFG->preventinstallaliases = true;

// ==============================================================================
// CACHE E SESSÕES
// ==============================================================================
// Redis para sessões (recomendado)
// \$CFG->session_handler_class = '\core\session\redis';
// \$CFG->session_redis_host = 'redis';
// \$CFG->session_redis_port = 6379;
// \$CFG->session_redis_database = 0;
// \$CFG->session_redis_prefix = 'moodle_sess_';
// \$CFG->session_redis_acquire_lock_timeout = 120;
// \$CFG->session_redis_lock_expire = 7200;

// ==============================================================================
// PERFORMANCE
// ==============================================================================
// Cache definitions
// \$CFG->alternative_cache_factory_class = 'cache_factory_disabled';

// Localização de cache (opcional)
// \$CFG->localcachedir = '/var/moodledata/localcache';

// ==============================================================================
// DEBUG (DESABILITAR EM PRODUÇÃO!)
// ==============================================================================
@error_reporting(E_ALL | E_STRICT);
@ini_set('display_errors', '${debug_display}');
\$CFG->debug = ${debug_level};
\$CFG->debugdisplay = ${debug_display};

// ==============================================================================
// CONFIGURAÇÕES DE EMAIL
// ==============================================================================
// Configure via Admin UI ou defina aqui
// \$CFG->smtphosts = 'smtp.example.com:587';
// \$CFG->smtpsecure = 'tls';
// \$CFG->smtpuser = 'user';
// \$CFG->smtppass = 'password';
// \$CFG->noreplyaddress = 'noreply@example.com';

// ==============================================================================
// UPGRADE E MANUTENÇÃO
// ==============================================================================
// Permite upgrades via linha de comando
\$CFG->upgradekey = '${MOODLE_UPGRADE_KEY:-}';

// Previne edição de config.php pela interface
\$CFG->disableupdateautodeploy = true;

// ==============================================================================
// INICIALIZAÇÃO DO MOODLE
// ==============================================================================
require_once(__DIR__ . '/lib/setup.php');
EOFCONFIG

    # Protege o arquivo de configuração
    chmod 440 "$config_file"
    
    log_info "config.php gerado com sucesso!"
}

# ==============================================================================
# CRIAÇÃO DE DIRETÓRIOS
# ==============================================================================
setup_directories() {
    log_info "Configurando diretórios..."
    
    # Diretório de dados do Moodle
    mkdir -p "$MOODLE_DATA_DIR"
    mkdir -p "$MOODLE_DATA_DIR/sessions"
    mkdir -p "$MOODLE_DATA_DIR/temp"
    mkdir -p "$MOODLE_DATA_DIR/cache"
    mkdir -p "$MOODLE_DATA_DIR/localcache"
    mkdir -p "$MOODLE_DATA_DIR/filedir"
    
    # Diretório de logs do PHP
    mkdir -p /var/log/php
    
    log_info "Diretórios configurados."
}

# ==============================================================================
# MAIN
# ==============================================================================
main() {
    log_info "=========================================="
    log_info "Iniciando Moodle Container"
    log_info "=========================================="
    
    # Executa verificações
    check_required_vars
    security_checks
    setup_directories
    wait_for_database
    configure_moodle
    
    log_info "=========================================="
    log_info "Moodle pronto! Iniciando PHP-FPM..."
    log_info "=========================================="
    
    # Executa o comando passado (php-fpm por padrão)
    exec "$@"
}

main "$@"
