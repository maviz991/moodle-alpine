# Moodle Docker - Instalação Segura

Dockerfile e configurações para uma instalação segura do Moodle LMS com banco de dados MySQL externo.

## 📋 Requisitos

- Docker Engine 20.10+
- Docker Compose 2.0+
- Servidor MySQL/MariaDB externo (ou use o container de desenvolvimento)
- Certificado SSL válido (Let's Encrypt recomendado)
- Mínimo 2GB RAM, 4GB recomendado

## 🚀 Quick Start

### 1. Clone e configure

```bash
# Clone ou copie os arquivos
cd moodle-docker

# Configure as variáveis de ambiente
cp .env.example .env

# Edite o .env com seus valores
nano .env
```

### 2. Gere credenciais seguras

```bash
# Gere salt do Moodle
echo "MOODLE_PASSWORD_SALT=$(openssl rand -hex 32)" >> .env

# Gere senha do banco
echo "MOODLE_DB_PASSWORD=$(openssl rand -base64 32)" >> .env

# Gere senha root MySQL (desenvolvimento)
echo "MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)" >> .env

# Gere senha Redis
echo "REDIS_PASSWORD=$(openssl rand -base64 32)" >> .env
```

### 3. Configure os certificados SSL

```bash
# Crie diretório de certificados
mkdir -p certs

# Use Let's Encrypt (recomendado) ou seus próprios certificados
# Os arquivos devem ser:
# - certs/fullchain.pem
# - certs/privkey.pem
```

### 4. Inicie os containers

```bash
# Construa a imagem
docker-compose build

# Inicie os serviços
docker-compose up -d

# Acompanhe os logs
docker-compose logs -f moodle
```

### 5. Finalize a instalação

Acesse `https://seu-dominio.com` e complete o wizard de instalação do Moodle.

## 🔒 Medidas de Segurança Implementadas

### Container e Sistema

| Medida | Descrição |
|--------|-----------|
| Usuário não-root | Container executa como usuário `moodle` (UID 1000) |
| Imagem mínima | Base Alpine Linux com superfície de ataque reduzida |
| Read-only onde possível | Moodledata é o único diretório com escrita |
| No new privileges | Flag de segurança que impede escalação |
| Resource limits | Limites de CPU e memória definidos |

### PHP

| Medida | Descrição |
|--------|-----------|
| expose_php = Off | Esconde versão do PHP nos headers |
| disable_functions | Funções perigosas desabilitadas |
| open_basedir | Acesso restrito a diretórios específicos |
| allow_url_include = Off | Bloqueia inclusão de arquivos remotos |
| Session hardening | Cookies HTTPOnly, Secure, SameSite |

### Nginx

| Medida | Descrição |
|--------|-----------|
| HTTPS obrigatório | Redirect HTTP → HTTPS |
| TLS 1.2+ apenas | Protocolos antigos desabilitados |
| Security headers | HSTS, CSP, X-Frame-Options, etc. |
| Rate limiting | Proteção contra brute force |
| Arquivos sensíveis bloqueados | config.php, .git, vendor, etc. |

### Banco de Dados

| Medida | Descrição |
|--------|-----------|
| Conexão via rede Docker | Não exposto externamente |
| Usuário dedicado | Sem acesso root |
| UTF8MB4 | Suporte completo a Unicode |

## 📁 Estrutura de Arquivos

```
moodle-docker/
├── Dockerfile                 # Imagem principal do Moodle
├── docker-compose.yml         # Orquestração dos serviços
├── .env.example              # Template de variáveis
├── README.md                 # Este arquivo
│
├── config/
│   ├── php-security.ini      # Hardening do PHP
│   ├── php-moodle.ini        # Configurações específicas Moodle
│   ├── opcache.ini           # Otimização de cache
│   └── php-fpm-security.conf # Hardening do PHP-FPM
│
├── nginx/
│   ├── moodle.conf           # Virtual host do Moodle
│   └── security-headers.conf # Headers de segurança
│
├── scripts/
│   ├── docker-entrypoint.sh  # Script de inicialização
│   └── healthcheck.sh        # Health check do container
│
├── certs/                    # Certificados SSL (não versionado)
└── logs/                     # Logs (não versionado)
    ├── nginx/
    └── php/
```

## 🔧 Configurações Importantes

### Usando MySQL/MariaDB Externo

Edite `docker-compose.yml` e remova o serviço `mysql`. Configure as variáveis:

```env
MOODLE_DB_HOST=seu-servidor-mysql.example.com
MOODLE_DB_PORT=3306
MOODLE_DB_NAME=moodle
MOODLE_DB_USER=moodle
MOODLE_DB_PASSWORD=sua-senha-segura
```

### Habilitando Redis para Sessões

No `config.php` do Moodle (ou descomente no script de entrypoint):

```php
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host = 'redis';
$CFG->session_redis_port = 6379;
$CFG->session_redis_auth = 'sua-senha-redis';
$CFG->session_redis_database = 0;
$CFG->session_redis_prefix = 'moodle_sess_';
```

### Content Security Policy (CSP)

A CSP configurada permite os recursos mais comuns. Se usar plugins que precisam de recursos externos, ajuste `nginx/security-headers.conf`:

```nginx
# Adicione domínios conforme necessário
script-src 'self' https://seu-cdn.com;
frame-src 'self' https://servico-externo.com;
```

## 🔄 Manutenção

### Backup

```bash
# Backup do moodledata
docker run --rm -v moodle-docker_moodledata:/data -v $(pwd)/backups:/backup alpine \
    tar czf /backup/moodledata-$(date +%Y%m%d).tar.gz -C /data .

# Backup do banco (se usando container MySQL)
docker exec moodle-mysql mysqldump -u root -p moodle > backups/moodle-db-$(date +%Y%m%d).sql
```

### Atualização do Moodle

```bash
# Para os serviços
docker-compose down

# Rebuild com nova versão
docker-compose build --build-arg MOODLE_VERSION=405 --no-cache

# Inicie e execute upgrade
docker-compose up -d
docker-compose exec moodle php admin/cli/upgrade.php
```

### Limpar cache do OPcache

```bash
docker-compose exec moodle php -r "opcache_reset();"
```

## 🐛 Troubleshooting

### Verificar logs

```bash
# Logs do Moodle/PHP
docker-compose logs moodle

# Logs do nginx
docker-compose logs nginx

# Logs do PHP em tempo real
tail -f logs/php/error.log
```

### Verificar status do PHP-FPM

```bash
curl http://localhost/php-fpm-status
```

### Testar conexão com banco

```bash
docker-compose exec moodle php -r "
    \$conn = new mysqli(getenv('MOODLE_DB_HOST'), getenv('MOODLE_DB_USER'), getenv('MOODLE_DB_PASSWORD'));
    echo \$conn->connect_error ? 'ERRO: '.\$conn->connect_error : 'OK';
"
```

## ⚠️ Avisos de Segurança

1. **Nunca** use `MOODLE_DEBUG=true` em produção
2. **Sempre** use HTTPS em produção
3. **Mantenha** o Moodle e dependências atualizados
4. **Monitore** os logs regularmente
5. **Faça backup** diário do moodledata e banco
6. **Restrinja** acesso ao `/admin` por IP se possível
7. **Use** senhas fortes (mínimo 16 caracteres)

## 📚 Referências

- [Moodle Security Recommendations](https://docs.moodle.org/en/Security_recommendations)
- [PHP Security Best Practices](https://www.php.net/manual/en/security.php)
- [Docker Security Best Practices](https://docs.docker.com/develop/security-best-practices/)
- [Nginx Security](https://nginx.org/en/docs/http/configuring_https_servers.html)

## 📄 Licença

Este projeto está sob licença MIT. O Moodle é licenciado sob GPLv3.
