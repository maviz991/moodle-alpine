# ==============================================================================
# Makefile - Moodle Docker Build & Management
# ==============================================================================

.PHONY: help setup-proxy build build-plugins push run stop logs shell clean verify-plugins

# Variáveis
REGISTRY ?= registry.cdhu.sp.gov.br
IMAGE_NAME ?= moodle
MOODLE_VERSION ?= 405
TAG ?= $(MOODLE_VERSION)-$(shell date +%Y%m%d)
FULL_IMAGE = $(REGISTRY)/$(IMAGE_NAME):$(TAG)
LATEST_IMAGE = $(REGISTRY)/$(IMAGE_NAME):latest

# ------------------------------------------------------------------------------
# PROXY DE BUILD
# Na rede da CDHU o proxy e obrigatorio. Sobrescreva com:
#   make build BUILD_PROXY=            (para buildar fora da rede, sem proxy)
#   make build BUILD_PROXY=http://outro:3128
# ------------------------------------------------------------------------------
BUILD_PROXY ?= http://10.71.48.17:8080
BUILD_NO_PROXY ?= localhost,127.0.0.1,::1,.cdhu.sp.gov.br,.sp.gov.br

PROXY_ARGS = --build-arg HTTP_PROXY=$(BUILD_PROXY) \
             --build-arg HTTPS_PROXY=$(BUILD_PROXY) \
             --build-arg NO_PROXY=$(BUILD_NO_PROXY)

# Cores
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help: ## Mostra esta ajuda
	@echo ""
	@echo "Moodle Docker - Comandos disponíveis:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Variáveis de ambiente:"
	@echo "  REGISTRY        = $(REGISTRY)"
	@echo "  IMAGE_NAME      = $(IMAGE_NAME)"
	@echo "  MOODLE_VERSION  = $(MOODLE_VERSION)"
	@echo "  TAG             = $(TAG)"
	@echo ""

# ==============================================================================
# BUILD
# ==============================================================================

setup-proxy: ## Configura WSL + Docker daemon para o proxy da CDHU (roda 1x, pede sudo)
	sudo bash scripts/setup-wsl-proxy.sh

build: ## Build imagem básica (sem plugins)
	@echo "$(GREEN)Building Moodle $(MOODLE_VERSION) (sem plugins)...$(NC)"
	docker build \
		--build-arg MOODLE_VERSION=$(MOODLE_VERSION) \
		$(PROXY_ARGS) \
		-t $(IMAGE_NAME):$(TAG) \
		-t $(IMAGE_NAME):latest \
		-f Dockerfile .
	@echo "$(GREEN)✓ Build concluído: $(IMAGE_NAME):$(TAG)$(NC)"

build-plugins: ## Build imagem com plugins (produção)
	@echo "$(GREEN)Building Moodle $(MOODLE_VERSION) com plugins...$(NC)"
	docker build \
		--build-arg MOODLE_VERSION=$(MOODLE_VERSION) \
		$(PROXY_ARGS) \
		-t $(IMAGE_NAME):$(TAG)-plugins \
		-t $(IMAGE_NAME):latest \
		-f Dockerfile.plugins .
	@echo "$(GREEN)✓ Build concluído: $(IMAGE_NAME):$(TAG)-plugins$(NC)"

build-no-cache: ## Build sem cache (força download)
	docker build --no-cache \
		--build-arg MOODLE_VERSION=$(MOODLE_VERSION) \
		$(PROXY_ARGS) \
		-t $(IMAGE_NAME):$(TAG)-plugins \
		-f Dockerfile.plugins .

# ==============================================================================
# REGISTRY
# ==============================================================================

push: ## Push imagem para registry
	@echo "$(GREEN)Pushing $(FULL_IMAGE)...$(NC)"
	docker tag $(IMAGE_NAME):$(TAG)-plugins $(FULL_IMAGE)
	docker tag $(IMAGE_NAME):$(TAG)-plugins $(LATEST_IMAGE)
	docker push $(FULL_IMAGE)
	docker push $(LATEST_IMAGE)
	@echo "$(GREEN)✓ Push concluído$(NC)"

pull: ## Pull imagem do registry
	docker pull $(LATEST_IMAGE)

# ==============================================================================
# DESENVOLVIMENTO
# ==============================================================================

run: ## Inicia ambiente de desenvolvimento
	docker-compose up -d
	@echo "$(GREEN)✓ Ambiente iniciado$(NC)"
	@echo "  Acesse: http://localhost:8080"

run-prod: ## Inicia com docker-compose de produção
	docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

stop: ## Para todos os containers
	docker-compose down

restart: ## Reinicia os containers
	docker-compose restart

logs: ## Mostra logs (use: make logs SERVICE=moodle)
	docker-compose logs -f $(SERVICE)

shell: ## Abre shell no container Moodle
	docker-compose exec moodle sh

shell-root: ## Abre shell como root
	docker-compose exec -u root moodle sh

# ==============================================================================
# PLUGINS
# ==============================================================================

list-plugins: ## Lista plugins configurados
	@./plugins/install-plugins.sh list

verify-plugins: ## Verifica plugins instalados no container
	docker-compose exec moodle sh -c 'find /var/www/html -name "version.php" -path "*/mod/*" -o -name "version.php" -path "*/blocks/*" -o -name "version.php" -path "*/local/*" | head -20'

install-plugin-local: ## Instala plugin local (use: make install-plugin-local PLUGIN=mod_xyz)
	@if [ -z "$(PLUGIN)" ]; then echo "Uso: make install-plugin-local PLUGIN=mod_xyz"; exit 1; fi
	@echo "$(GREEN)Instalando $(PLUGIN)...$(NC)"
	docker-compose exec moodle sh -c 'cd /var/www/html && php admin/cli/upgrade.php --non-interactive'

# ==============================================================================
# MANUTENÇÃO MOODLE
# ==============================================================================

upgrade: ## Executa upgrade do Moodle
	docker-compose exec moodle php admin/cli/upgrade.php --non-interactive

purge-caches: ## Limpa caches do Moodle
	docker-compose exec moodle php admin/cli/purge_caches.php

cron: ## Executa cron do Moodle manualmente
	docker-compose exec moodle php admin/cli/cron.php

maintenance-on: ## Ativa modo de manutenção
	docker-compose exec moodle php admin/cli/maintenance.php --enable

maintenance-off: ## Desativa modo de manutenção
	docker-compose exec moodle php admin/cli/maintenance.php --disable

# ==============================================================================
# BANCO DE DADOS
# ==============================================================================

db-shell: ## Abre shell MySQL
	docker-compose exec mysql mysql -u root -p

db-backup: ## Backup do banco de dados
	@mkdir -p backups
	docker-compose exec mysql mysqldump -u root -p$(MYSQL_ROOT_PASSWORD) moodle > backups/moodle-$(shell date +%Y%m%d-%H%M%S).sql
	@echo "$(GREEN)✓ Backup salvo em backups/$(NC)"

db-restore: ## Restore do banco (use: make db-restore FILE=backup.sql)
	@if [ -z "$(FILE)" ]; then echo "Uso: make db-restore FILE=backups/moodle-xxx.sql"; exit 1; fi
	docker-compose exec -T mysql mysql -u root -p$(MYSQL_ROOT_PASSWORD) moodle < $(FILE)

# ==============================================================================
# LIMPEZA
# ==============================================================================

clean: ## Remove containers e volumes
	docker-compose down -v
	docker rmi $(IMAGE_NAME):$(TAG) $(IMAGE_NAME):latest 2>/dev/null || true

clean-all: ## Remove tudo (incluindo imagens)
	docker-compose down -v --rmi all
	docker system prune -f

# ==============================================================================
# TESTES
# ==============================================================================

test-config: ## Verifica configuração
	@echo "$(GREEN)Verificando .env...$(NC)"
	@test -f .env || (echo "$(YELLOW)AVISO: .env não existe. Copie de .env.example$(NC)" && exit 1)
	@echo "$(GREEN)Verificando plugins.json...$(NC)"
	@jq empty plugins/plugins.json && echo "$(GREEN)✓ plugins.json válido$(NC)"

test-build: ## Testa build da imagem
	docker build --target builder $(PROXY_ARGS) -f Dockerfile.plugins -t test-builder .
	@echo "$(GREEN)✓ Build test passou$(NC)"

# ==============================================================================
# CI/CD
# ==============================================================================

ci-build: ## Build para CI (com tag do commit)
	docker build \
		--build-arg MOODLE_VERSION=$(MOODLE_VERSION) \
		$(PROXY_ARGS) \
		-t $(REGISTRY)/$(IMAGE_NAME):$(shell git rev-parse --short HEAD) \
		-f Dockerfile.plugins .

ci-push: ## Push para CI
	docker push $(REGISTRY)/$(IMAGE_NAME):$(shell git rev-parse --short HEAD)
