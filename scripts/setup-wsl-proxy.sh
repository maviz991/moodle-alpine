#!/usr/bin/env bash
# ==============================================================================
# setup-wsl-proxy.sh - Configura WSL + Docker daemon para o proxy FortiGate CDHU
#
# Resolve os 3 motivos pelos quais o build/pull falha na rede da CDHU:
#   1. CA da CDHU nao instalada no trust store do WSL
#   2. Docker daemon sem proxy configurado (pull da imagem base da timeout)
#   3. Variavel de ambiente http_proxy=http://PROXY:8080 herdada do Windows,
#      onde o host "PROXY" nao resolve dentro do WSL
#
# Uso:  sudo bash scripts/setup-wsl-proxy.sh
# ==============================================================================
set -euo pipefail

PROXY_HOST="${PROXY_HOST:-10.71.48.17}"
PROXY_PORT="${PROXY_PORT:-8080}"
PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
NO_PROXY_LIST="localhost,127.0.0.1,::1,*.cdhu.sp.gov.br,*.sp.gov.br,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CA_DIR="${PROJECT_DIR}/config/ca"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}!!!${NC} $*"; }
die()   { echo -e "${RED}ERRO:${NC} $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Rode com sudo: sudo bash scripts/setup-wsl-proxy.sh"

# ------------------------------------------------------------------------------
# 0. Conectividade com o proxy
# ------------------------------------------------------------------------------
info "Testando ${PROXY_URL} ..."
timeout 5 bash -c "cat < /dev/null > /dev/tcp/${PROXY_HOST}/${PROXY_PORT}" 2>/dev/null \
    || die "Proxy ${PROXY_HOST}:${PROXY_PORT} inacessivel. Voce esta na rede da CDHU / VPN ligada?"
info "Proxy acessivel."

# ------------------------------------------------------------------------------
# 1. Extrai a CA raiz atual do proxy (nao depende de arquivo enviado por colega)
# ------------------------------------------------------------------------------
command -v openssl >/dev/null 2>&1 || {
    warn "openssl ausente, instalando (ignorando SSL so nesta etapa)..."
    apt-get -o Acquire::https::Verify-Peer=false -o Acquire::https::Verify-Host=false update -qq
    apt-get -o Acquire::https::Verify-Peer=false -o Acquire::https::Verify-Host=false install -y openssl ca-certificates
}

info "Extraindo cadeia de certificados do proxy..."
TMP_CHAIN="$(mktemp -d)"
trap 'rm -rf "$TMP_CHAIN"' EXIT

# Importante: limpa proxy do ambiente, senao o openssl tenta usar o host "PROXY"
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
    openssl s_client -proxy "${PROXY_HOST}:${PROXY_PORT}" \
        -connect registry-1.docker.io:443 -servername registry-1.docker.io \
        -showcerts </dev/null 2>/dev/null \
  | awk '/BEGIN CERT/{f=1} f{print > ("'"$TMP_CHAIN"'/cert" n ".pem")} /END CERT/{f=0; n++}'

shopt -s nullglob
CHAIN=("$TMP_CHAIN"/cert*.pem)
[ "${#CHAIN[@]}" -ge 2 ] || die "Nao consegui extrair a cadeia do proxy (obtive ${#CHAIN[@]} certificados)."

mkdir -p "$CA_DIR"
FOUND=0
for f in "${CHAIN[@]}"; do
    # so instala certificados que sao CA (ignora a folha *.docker.com)
    if openssl x509 -in "$f" -noout -text 2>/dev/null | grep -q "CA:TRUE"; then
        subj="$(openssl x509 -in "$f" -noout -subject)"
        slug="$(openssl x509 -in "$f" -noout -subject -nameopt multiline \
                | awk -F'= ' '/commonName/{print $2}' | tr -cd '[:alnum:]._-' )"
        [ -n "$slug" ] || slug="ca${FOUND}"
        cp "$f" "${CA_DIR}/${slug}.crt"
        info "CA encontrada: ${subj}"
        FOUND=$((FOUND+1))
    fi
done
[ "$FOUND" -gt 0 ] || die "Nenhuma CA encontrada na cadeia do proxy."
info "${FOUND} CA(s) salvas em config/ca/"

# ------------------------------------------------------------------------------
# 2. Instala as CAs no trust store do WSL (remove as antigas/invalidas)
# ------------------------------------------------------------------------------
info "Limpando CAs antigas do FortiGate no trust store..."
rm -f /usr/local/share/ca-certificates/fortigate*.crt \
      /usr/local/share/ca-certificates/cdhu*.crt \
      /usr/local/share/ca-certificates/10.71.*.crt

for f in "${CA_DIR}"/*.crt; do
    cp "$f" "/usr/local/share/ca-certificates/$(basename "$f")"
done

info "Atualizando bundle de CAs do sistema..."
update-ca-certificates

# ------------------------------------------------------------------------------
# 3. Configura proxy do Docker daemon (systemd drop-in)
#    Sem isso o "docker pull" da context deadline exceeded.
# ------------------------------------------------------------------------------
info "Configurando proxy do Docker daemon..."
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
# Gerado por scripts/setup-wsl-proxy.sh
[Service]
Environment="HTTP_PROXY=${PROXY_URL}"
Environment="HTTPS_PROXY=${PROXY_URL}"
Environment="NO_PROXY=${NO_PROXY_LIST}"
EOF

# ------------------------------------------------------------------------------
# 4. Corrige o http_proxy=http://PROXY:8080 herdado do Windows
#    O host "PROXY" nao resolve no WSL, entao todo curl/apt/git falha.
# ------------------------------------------------------------------------------
info "Corrigindo variaveis de proxy do shell (host 'PROXY' nao resolve no WSL)..."
cat > /etc/profile.d/zz-cdhu-proxy.sh <<EOF
# Gerado por scripts/setup-wsl-proxy.sh
# O Windows exporta http_proxy=http://PROXY:8080 via WSLENV, mas o hostname
# "PROXY" nao resolve dentro do WSL. Reescreve para o IP real.
export http_proxy="${PROXY_URL}"
export https_proxy="${PROXY_URL}"
export HTTP_PROXY="${PROXY_URL}"
export HTTPS_PROXY="${PROXY_URL}"
export no_proxy="${NO_PROXY_LIST}"
export NO_PROXY="${NO_PROXY_LIST}"
EOF
chmod 644 /etc/profile.d/zz-cdhu-proxy.sh

# ------------------------------------------------------------------------------
# 5. Reinicia o daemon
# ------------------------------------------------------------------------------
info "Reiniciando Docker daemon..."
systemctl daemon-reload
systemctl restart docker
sleep 3

# ------------------------------------------------------------------------------
# 6. Verificacao
# ------------------------------------------------------------------------------
echo ""
info "Verificando proxy do daemon:"
docker info 2>/dev/null | grep -iE "http proxy|https proxy|no proxy" || warn "daemon nao reportou proxy"

echo ""
info "Testando docker pull..."
if timeout 120 docker pull hello-world >/dev/null 2>&1; then
    echo -e "${GREEN}✓ docker pull funcionando${NC}"
else
    die "docker pull ainda falha. Rode: docker pull hello-world  e veja o erro."
fi

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN} Setup concluido.${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo "Abra um shell NOVO (para pegar o /etc/profile.d) e rode o build:"
echo ""
echo "    cd ${PROJECT_DIR}"
echo "    make build"
echo ""
