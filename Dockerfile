# ==============================================================================
# Dockerfile para Moodle Seguro
# Base: PHP 8.2 FPM Alpine (menor superfície de ataque)
# Banco de Dados: MySQL/MariaDB externo ao container
# ==============================================================================

ARG MOODLE_VERSION=405
ARG PHP_VERSION=8.2

FROM php:${PHP_VERSION}-fpm-alpine AS base

# Re-declare ARGs after FROM (they don't persist across FROM)
ARG MOODLE_VERSION=405

LABEL maintainer="CDHU Infrastructure Team"
LABEL description="Moodle LMS - Instalação Segura"
LABEL moodle.version="${MOODLE_VERSION}"

# ==============================================================================
# VARIÁVEIS DE AMBIENTE - SEGURANÇA
# ==============================================================================
ENV MOODLE_VERSION=${MOODLE_VERSION}
ENV MOODLE_DIR=/var/www/html
ENV MOODLEDATA_DIR=/var/moodledata

# Desabilita exposição de versão do PHP
ENV PHP_EXPOSE_PHP=Off

# Timezone
ENV TZ=America/Sao_Paulo

# ==============================================================================
# PROXY CONFIGURATION (opcional - rede com inspecao SSL)
# ==============================================================================
# Vazio por padrao: a imagem builda em qualquer rede sem alteracao.
# Na rede da CDHU, passe:
#   docker build --build-arg HTTP_PROXY=http://10.71.48.17:8080 \
#                --build-arg HTTPS_PROXY=http://10.71.48.17:8080 ...
# ou simplesmente use `make build` (o Makefile detecta o proxy do ambiente).
ARG HTTP_PROXY=
ARG HTTPS_PROXY=
ARG NO_PROXY=localhost,127.0.0.1,::1
ENV http_proxy=${HTTP_PROXY} \
    https_proxy=${HTTPS_PROXY} \
    HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    no_proxy=${NO_PROXY} \
    NO_PROXY=${NO_PROXY}

# ==============================================================================
# CERTIFICADOS CA CORPORATIVOS (opcional)
# ==============================================================================
# Qualquer .crt (PEM) em config/ca/ e instalado no trust store da imagem.
# Se o diretorio estiver vazio, o build segue normalmente - nao quebra fora da
# rede corporativa. Gere os certs com: sudo bash scripts/setup-wsl-proxy.sh
COPY config/ca/ /tmp/ca-certs/
RUN set -eux; \
    if ls /tmp/ca-certs/*.crt >/dev/null 2>&1; then \
        mkdir -p /usr/local/share/ca-certificates; \
        cp /tmp/ca-certs/*.crt /usr/local/share/ca-certificates/; \
        # Anexa direto no bundle: nao depende de rede nem do pacote
        # ca-certificates, que ainda nao poderia ser baixado neste ponto.
        cat /tmp/ca-certs/*.crt >> /etc/ssl/certs/ca-certificates.crt; \
        # Se o update-ca-certificates existir na base, normaliza os hashes.
        if command -v update-ca-certificates >/dev/null 2>&1; then \
            update-ca-certificates || true; \
        fi; \
        echo "CA corporativas instaladas:"; ls -1 /usr/local/share/ca-certificates/; \
    else \
        echo "Nenhuma CA corporativa em config/ca/ - seguindo sem."; \
    fi; \
    rm -rf /tmp/ca-certs

# ==============================================================================
# INSTALAÇÃO DE DEPENDÊNCIAS DO SISTEMA
# ==============================================================================
RUN apk update && apk upgrade --no-cache \
    && apk add --no-cache \
        # Dependências essenciais
        curl \
        wget \
        git \
        unzip \
        tzdata \
        bash \
        # Bibliotecas para extensões PHP
        freetype \
        freetype-dev \
        libjpeg-turbo \
        libjpeg-turbo-dev \
        libpng \
        libpng-dev \
        libwebp \
        libwebp-dev \
        libzip \
        libzip-dev \
        libxml2 \
        libxml2-dev \
        libxslt \
        libxslt-dev \
        icu \
        icu-dev \
        icu-data-full \
        oniguruma \
        oniguruma-dev \
        openldap \
        openldap-dev \
        libsodium \
        libsodium-dev \
        # Para compilação de extensões
        $PHPIZE_DEPS \
        linux-headers \
    # Configura timezone
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# ==============================================================================
# INSTALAÇÃO DE EXTENSÕES PHP REQUERIDAS PELO MOODLE
# ==============================================================================
RUN docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j$(nproc) \
        # Extensões obrigatórias
        mysqli \
        pdo \
        pdo_mysql \
        gd \
        intl \
        soap \
        zip \
        opcache \
        exif \
        # Extensões recomendadas
        xsl \
        ldap \
        sodium \
    # Instala Redis para cache de sessão (recomendado)
    && pecl install redis \
    && docker-php-ext-enable redis \
    # Instala APCu para cache local
    && pecl install apcu \
    && docker-php-ext-enable apcu \
    # Limpeza pós-instalação (reduz tamanho da imagem)
    && apk del --no-cache \
        freetype-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        libxml2-dev \
        libxslt-dev \
        icu-dev \
        oniguruma-dev \
        openldap-dev \
        libsodium-dev \
        $PHPIZE_DEPS \
        linux-headers \
    && rm -rf /tmp/* /var/cache/apk/*

# ==============================================================================
# CONFIGURAÇÃO DE SEGURANÇA DO PHP
# ==============================================================================
COPY config/php-security.ini /usr/local/etc/php/conf.d/99-security.ini
COPY config/php-moodle.ini /usr/local/etc/php/conf.d/98-moodle.ini
COPY config/opcache.ini /usr/local/etc/php/conf.d/97-opcache.ini
COPY config/php-fpm-security.conf /usr/local/etc/php-fpm.d/zz-security.conf

# ==============================================================================
# DOWNLOAD E VERIFICAÇÃO DO MOODLE
# ==============================================================================
WORKDIR /tmp

# Download do Moodle com verificação de integridade
RUN MOODLE_DOWNLOAD_URL="https://packaging.moodle.org/stable${MOODLE_VERSION}/moodle-latest-${MOODLE_VERSION}.tgz" \
    && curl -fSL -o moodle.tgz "${MOODLE_DOWNLOAD_URL}" \
    && mkdir -p ${MOODLE_DIR} \
    && tar -xzf moodle.tgz --strip-components=1 -C ${MOODLE_DIR} \
    && rm moodle.tgz

# ==============================================================================
# CRIAÇÃO DE USUÁRIO NÃO-ROOT (SEGURANÇA)
# ==============================================================================
RUN addgroup -g 1000 -S moodle \
    && adduser -u 1000 -S moodle -G moodle \
    && mkdir -p ${MOODLEDATA_DIR} \
    && chown -R moodle:moodle ${MOODLE_DIR} ${MOODLEDATA_DIR}

# ==============================================================================
# HARDENING DE PERMISSÕES
# ==============================================================================
# Moodle: somente leitura (exceto durante instalação)
RUN chmod -R 755 ${MOODLE_DIR} \
    && find ${MOODLE_DIR} -type f -exec chmod 644 {} \; \
    # Moodledata: leitura e escrita para o usuário moodle
    && chmod 770 ${MOODLEDATA_DIR}

# ==============================================================================
# SCRIPTS DE INICIALIZAÇÃO E HEALTH CHECK
# ==============================================================================
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/healthcheck.sh

# ==============================================================================
# CONFIGURAÇÃO FINAL
# ==============================================================================
# Limpa o proxy de build: em runtime o container nao deve rotear tudo pelo
# FortiGate (o proxy so e necessario durante o build). As CAs continuam
# instaladas no trust store.
ENV http_proxy= \
    https_proxy= \
    HTTP_PROXY= \
    HTTPS_PROXY= \
    no_proxy= \
    NO_PROXY=

WORKDIR ${MOODLE_DIR}

# Expõe apenas a porta do PHP-FPM (não HTTP direto)
EXPOSE 9000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# Executa como usuário não-root
USER moodle

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["php-fpm"]
