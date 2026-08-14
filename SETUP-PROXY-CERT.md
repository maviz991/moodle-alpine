# Configuração do Certificado de Proxy SSL (FortiGate)

> **Contexto:** A rede usa um proxy FortiGate que faz inspeção SSL.
> O sistema precisa confiar no CA do FortiGate para `docker build`, `docker pull` e `apt` funcionarem.

---

## Pré-requisito — Instalar o OpenSSL

### Caso normal (apt funcionando)

```bash
sudo apt update && sudo apt install -y openssl ca-certificates
```

### ⚠️ Se o `apt` também falhar com erro SSL

O `apt` em si pode estar bloqueado pelo proxy. Solução: ignorar SSL só nessa instalação inicial:

```bash
# Atualiza ignorando verificação SSL (só desta vez)
sudo apt -o Acquire::https::Verify-Peer=false \
         -o Acquire::https::Verify-Host=false \
         update

# Instala openssl e ca-certificates
sudo apt -o Acquire::https::Verify-Peer=false \
         -o Acquire::https::Verify-Host=false \
         install -y openssl ca-certificates
```

> Após instalar o openssl e adicionar o CA do FortiGate (passos abaixo),
> o `apt` voltará a funcionar normalmente sem precisar do flag.

---

## Passo 1 - Extrair o certificado CA do proxy

Execute no terminal WSL:

```bash
echo QUIT | openssl s_client \
  -proxy 10.71.48.17:8080 \
  -connect google.com:443 \
  -showcerts 2>/dev/null \
  | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
  | awk 'BEGIN{n=0} /BEGIN CERT/{n++} n==2{print} /END CERT/ && n==2{exit}' \
  > /tmp/fortigate_proxy.crt
```

Verificação:

```bash
openssl x509 -in /tmp/fortigate_proxy.crt -noout -subject -dates
```

Saída esperada (algo parecido com):

```
subject=C=US, ST=California, O=Fortinet, CN=<nome-do-fortigate>
notBefore=...
notAfter=...
```

> O `CN=` varia conforme o equipamento FortiGate da unidade (ex: `CN=FG180FTK23901473`, `CN=wr2`, etc.).
> O importante é que apareça `O=Fortinet` e as datas sejam válidas.

---

## Passo 2 - Instalar o certificado no sistema (WSL/Debian)

```bash
# Copia para o store de CAs do sistema
sudo cp /tmp/fortigate_proxy.crt \
     /usr/local/share/ca-certificates/fortigate-proxy.crt

# Atualiza o bundle de CAs
sudo update-ca-certificates
```

Saída esperada:

```
Updating certificates in /etc/ssl/certs...
1 added, 0 removed; done.
```

---

## Passo 3 - Copiar o cert para o projeto

Primeiro, confirme qual arquivo usar:

```bash
ls -lh /tmp/*.crt
```

> Se o arquivo tiver outro nome (ex: `fortigate_wr2.crt`), use esse nome nos passos abaixo.

### Opção A — Windows Explorer (mais fácil)

1. Abra o Explorer e na barra de endereço digite:
   ```
   \\wsl$\Debian\tmp
   ```
2. Copie o arquivo `.crt` correto
3. Cole em `C:\Users\<seu-usuario>\moodle-alpine\moodle-docker-alpine\config\`
4. **Renomeie para `fortigate_proxy.crt`** se tiver outro nome

### Opção B — Terminal WSL

```bash
cp /tmp/fortigate_proxy.crt \
   "/mnt/c/Users/$(whoami | cut -d'\' -f2)/moodle-alpine/moodle-docker-alpine/config/fortigate_proxy.crt"
```

---

## Passo 4 - Reiniciar o Docker daemon

O daemon precisa recarregar o trust store para aceitar o pull de imagens:

```bash
sudo service docker restart
```

Verifique se subiu:

```bash
docker info | head -5
```

---

## Passo 5 - Testar o build

```bash
cd /mnt/c/Users/<SEU_USUARIO>/moodle-alpine/moodle-docker-alpine

# Build de desenvolvimento (Dockerfile básico)
docker build -f Dockerfile -t moodle-dev:test .
```

Para subir o ambiente completo de dev:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

Acesse em: **http://localhost:8080**

---

## Troubleshooting

| Erro | Causa | Solução |
|---|---|---|
| `x509: certificate signed by unknown authority` | CA não instalado no Docker daemon | Refaça os passos 2 e 4 |
| `COPY failed: file not found: config/fortigate_proxy.crt` | Cert não copiado para o projeto | Refaça o passo 3 |
| `tls: failed to verify certificate` | Cert expirado ou errado | Refaça o passo 1 |
| `openssl: command not found` | openssl não instalado | Veja seção **Pré-requisito** acima |
| `apt` falha com erro SSL | Proxy bloqueia o próprio apt | Use o flag `Acquire::https::Verify-Peer=false` (ver Pré-requisito) |
| `sudo: service: command not found` | Docker não registrado como serviço | Tente `sudo dockerd &` ou abra o Docker Desktop |

---

## Observações

- O certificado extraído é válido até **2035** (não precisa refazer tão cedo).
- O arquivo `config/fortigate_proxy.crt` **não deve ser commitado**, deve está no `.gitignore`.

