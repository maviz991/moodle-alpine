#!/bin/bash
# ==============================================================================
# Script de Instalação de Plugins do Moodle
# Lê plugins.json e instala no diretório correto
# ==============================================================================
set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Diretórios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_JSON="${SCRIPT_DIR}/plugins.json"
MOODLE_DIR="${MOODLE_DIR:-/var/www/html}"
TEMP_DIR="/tmp/moodle-plugins"

# Mapeamento de tipo para diretório
declare -A TYPE_DIRS=(
    ["mod"]="mod"
    ["block"]="blocks"
    ["theme"]="theme"
    ["auth"]="auth"
    ["enrol"]="enrol"
    ["local"]="local"
    ["report"]="report"
    ["admin"]="admin/tool"
    ["tool"]="admin/tool"
    ["format"]="course/format"
    ["gradeexport"]="grade/export"
    ["gradeimport"]="grade/import"
    ["gradereport"]="grade/report"
    ["qtype"]="question/type"
    ["qbehaviour"]="question/behaviour"
    ["qformat"]="question/format"
    ["filter"]="filter"
    ["editor"]="lib/editor"
    ["atto"]="lib/editor/atto/plugins"
    ["tinymce"]="lib/editor/tinymce/plugins"
    ["repository"]="repository"
    ["portfolio"]="portfolio"
    ["plagiarism"]="plagiarism"
    ["availability"]="availability/condition"
    ["calendartype"]="calendar/type"
    ["message"]="message/output"
    ["profilefield"]="user/profile/field"
    ["assignsubmission"]="mod/assign/submission"
    ["assignfeedback"]="mod/assign/feedback"
    ["booktool"]="mod/book/tool"
    ["datafield"]="mod/data/field"
    ["datapreset"]="mod/data/preset"
    ["ltisource"]="mod/lti/source"
    ["ltiservice"]="mod/lti/service"
    ["quiz"]="mod/quiz/report"
    ["quizaccess"]="mod/quiz/accessrule"
    ["scormreport"]="mod/scorm/report"
    ["workshopallocation"]="mod/workshop/allocation"
    ["workshopeval"]="mod/workshop/eval"
    ["workshopform"]="mod/workshop/form"
    ["cachestore"]="cache/stores"
    ["cachelock"]="cache/locks"
    ["fileconverter"]="files/converter"
    ["search"]="search/engine"
    ["media"]="media/player"
    ["contenttype"]="contentbank/contenttype"
    ["customfield"]="customfield/field"
    ["paygw"]="payment/gateway"
    ["mlbackend"]="lib/mlbackend"
)

# Verifica dependências
check_dependencies() {
    log_step "Verificando dependências..."
    
    local missing=0
    for cmd in jq curl unzip git; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Comando não encontrado: $cmd"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        log_error "Instale as dependências faltantes e tente novamente"
        exit 1
    fi
    
    if [ ! -f "$PLUGINS_JSON" ]; then
        log_error "Arquivo não encontrado: $PLUGINS_JSON"
        exit 1
    fi
    
    log_info "Dependências OK"
}

# Obtém diretório de destino baseado no tipo
get_plugin_dir() {
    local plugin_type="$1"
    local plugin_name="$2"
    
    local base_dir="${TYPE_DIRS[$plugin_type]}"
    if [ -z "$base_dir" ]; then
        log_warn "Tipo de plugin desconhecido: $plugin_type, usando 'local'"
        base_dir="local"
    fi
    
    # Remove prefixo do tipo do nome (ex: mod_hvp -> hvp)
    local dir_name="${plugin_name#${plugin_type}_}"
    
    echo "${MOODLE_DIR}/${base_dir}/${dir_name}"
}

# Baixa plugin do GitHub
download_from_github() {
    local repo="$1"
    local version="$2"
    local dest="$3"
    
    local url="https://github.com/${repo}/archive/refs/tags/${version}.tar.gz"
    local temp_file="${TEMP_DIR}/plugin.tar.gz"
    local temp_extract="${TEMP_DIR}/extract"
    
    log_info "Baixando de: $url"
    
    # Tenta baixar a tag, se falhar tenta como branch
    if ! curl -fSL -o "$temp_file" "$url" 2>/dev/null; then
        url="https://github.com/${repo}/archive/refs/heads/${version}.tar.gz"
        log_warn "Tag não encontrada, tentando branch: $url"
        curl -fSL -o "$temp_file" "$url"
    fi
    
    # Extrai
    mkdir -p "$temp_extract"
    tar -xzf "$temp_file" -C "$temp_extract"
    
    # Move para destino (remove diretório de versão do GitHub)
    local extracted_dir=$(ls -d ${temp_extract}/*/ | head -1)
    mkdir -p "$(dirname "$dest")"
    mv "$extracted_dir" "$dest"
    
    # Limpa
    rm -rf "$temp_file" "$temp_extract"
}

# Baixa plugin de URL direta
download_from_url() {
    local url="$1"
    local dest="$2"
    
    local temp_file="${TEMP_DIR}/plugin.zip"
    local temp_extract="${TEMP_DIR}/extract"
    
    log_info "Baixando de: $url"
    curl -fSL -o "$temp_file" "$url"
    
    # Extrai
    mkdir -p "$temp_extract"
    unzip -q "$temp_file" -d "$temp_extract"
    
    # Move para destino
    local extracted_dir=$(ls -d ${temp_extract}/*/ | head -1)
    mkdir -p "$(dirname "$dest")"
    mv "$extracted_dir" "$dest"
    
    # Limpa
    rm -rf "$temp_file" "$temp_extract"
}

# Clona plugin do Git
clone_from_git() {
    local repo="$1"
    local version="$2"
    local dest="$3"
    
    local url="https://github.com/${repo}.git"
    
    log_info "Clonando de: $url (${version})"
    git clone --depth 1 --branch "$version" "$url" "$dest"
    
    # Remove .git para reduzir tamanho
    rm -rf "${dest}/.git"
}

# Instala um plugin
install_plugin() {
    local name="$1"
    local type="$2"
    local source="$3"
    local version="$4"
    local repo="$5"
    local url="$6"
    
    local dest=$(get_plugin_dir "$type" "$name")
    
    log_step "Instalando: $name ($type) -> $dest"
    
    # Verifica se já existe
    if [ -d "$dest" ]; then
        if [ -f "${dest}/version.php" ]; then
            local current_version=$(grep -oP "plugin->version\s*=\s*\K[0-9]+" "${dest}/version.php" || echo "unknown")
            log_warn "Plugin já existe (versão: $current_version). Removendo..."
        fi
        rm -rf "$dest"
    fi
    
    # Cria diretório temporário
    mkdir -p "$TEMP_DIR"
    
    case "$source" in
        "github")
            download_from_github "$repo" "$version" "$dest"
            ;;
        "git")
            clone_from_git "$repo" "$version" "$dest"
            ;;
        "url")
            download_from_url "$url" "$dest"
            ;;
        *)
            log_error "Fonte desconhecida: $source"
            return 1
            ;;
    esac
    
    # Verifica se instalou corretamente
    if [ ! -f "${dest}/version.php" ]; then
        log_error "Instalação falhou - version.php não encontrado em $dest"
        return 1
    fi
    
    # Ajusta permissões
    chmod -R 755 "$dest"
    find "$dest" -type f -exec chmod 644 {} \;
    
    log_info "✓ $name instalado com sucesso"
}

# Processa todos os plugins do manifesto
process_plugins() {
    log_step "Processando manifesto de plugins..."
    
    local fail_on_error=$(jq -r '.settings.fail_on_error // true' "$PLUGINS_JSON")
    local total=$(jq '[.plugins[] | select(.enabled == true)] | length' "$PLUGINS_JSON")
    local count=0
    local failed=0
    
    log_info "Total de plugins habilitados: $total"
    echo ""
    
    # Itera sobre plugins habilitados
    while IFS= read -r plugin; do
        local name=$(echo "$plugin" | jq -r '.name')
        local type=$(echo "$plugin" | jq -r '.type')
        local source=$(echo "$plugin" | jq -r '.source')
        local version=$(echo "$plugin" | jq -r '.version')
        local repo=$(echo "$plugin" | jq -r '.repo // empty')
        local url=$(echo "$plugin" | jq -r '.url // empty')
        
        count=$((count + 1))
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "[$count/$total] Processando: $name"
        
        if install_plugin "$name" "$type" "$source" "$version" "$repo" "$url"; then
            :
        else
            failed=$((failed + 1))
            if [ "$fail_on_error" = "true" ]; then
                log_error "Abortando devido a erro (fail_on_error=true)"
                exit 1
            fi
        fi
        
    done < <(jq -c '.plugins[] | select(.enabled == true)' "$PLUGINS_JSON")
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ $failed -gt 0 ]; then
        log_warn "Instalação concluída com $failed erro(s)"
        return 1
    else
        log_info "✓ Todos os $total plugins instalados com sucesso!"
    fi
}

# Limpa arquivos temporários
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Lista plugins instalados
list_plugins() {
    log_step "Plugins configurados em plugins.json:"
    echo ""
    
    jq -r '.plugins[] | 
        if .enabled then "  ✓ " else "  ✗ " end + 
        .name + " (" + .type + ") - " + .version + 
        if .enabled then "" else " [DESABILITADO]" end' "$PLUGINS_JSON"
    
    echo ""
}

# Verifica plugins instalados no Moodle
verify_plugins() {
    log_step "Verificando plugins instalados..."
    echo ""
    
    while IFS= read -r plugin; do
        local name=$(echo "$plugin" | jq -r '.name')
        local type=$(echo "$plugin" | jq -r '.type')
        local dest=$(get_plugin_dir "$type" "$name")
        
        if [ -f "${dest}/version.php" ]; then
            local version=$(grep -oP "plugin->version\s*=\s*\K[0-9]+" "${dest}/version.php" 2>/dev/null || echo "?")
            echo -e "  ${GREEN}✓${NC} $name (v$version) -> $dest"
        else
            echo -e "  ${RED}✗${NC} $name -> NÃO ENCONTRADO"
        fi
        
    done < <(jq -c '.plugins[] | select(.enabled == true)' "$PLUGINS_JSON")
    
    echo ""
}

# Main
main() {
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "       Moodle Plugin Installer"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    
    trap cleanup EXIT
    
    case "${1:-install}" in
        "install")
            check_dependencies
            process_plugins
            ;;
        "list")
            list_plugins
            ;;
        "verify")
            check_dependencies
            verify_plugins
            ;;
        "help"|"-h"|"--help")
            echo "Uso: $0 [comando]"
            echo ""
            echo "Comandos:"
            echo "  install   Instala plugins do plugins.json (padrão)"
            echo "  list      Lista plugins configurados"
            echo "  verify    Verifica plugins instalados"
            echo "  help      Mostra esta ajuda"
            echo ""
            echo "Variáveis de ambiente:"
            echo "  MOODLE_DIR   Diretório do Moodle (padrão: /var/www/html)"
            ;;
        *)
            log_error "Comando desconhecido: $1"
            exit 1
            ;;
    esac
}

main "$@"
