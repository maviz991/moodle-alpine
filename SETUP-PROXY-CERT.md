# Configuração do Certificado de Proxy SSL (FortiGate)

### Instalar o OpenSSL (se não tiver)

```bash
sudo apt update && sudo apt install -y openssl ca-certificates
```

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
subject=C=US, ST=California, O=Fortinet, CN=FG180FTK23901473
notBefore=Jun 17 19:03:24 2025 GMT
notAfter=Jun 18 19:03:24 2035 GMT
```

> Se a saída estiver vazia ou der erro, o cert não foi extraído - verifique se o proxy está acessível.

---

## Passo 2 - Instalar o certificado no sistema (WSL/Debian)

```bash
# Copia para o store de CAs do sistema
sudo cp /tmp/fortigate_proxy.crt \
     /usr/local/share/ca-certificates/fortigate-fg180ftk23901473.crt

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

O Dockerfile precisa do cert em `config/fortigate_proxy.crt`:

```bash
cp /tmp/fortigate_proxy.crt \
   /mnt/c/Users/<SEU_USUARIO>/moodle-alpine/moodle-docker-alpine/config/fortigate_proxy.crt
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
| `openssl: command not found` | openssl não instalado | `sudo apt install -y openssl` |
| `sudo: service: command not found` | Docker não registrado como serviço | Tente `sudo dockerd &` ou abra o Docker Desktop |

---

## Observações

- O certificado extraído é válido até **2035** (não precisa refazer tão cedo).
- O arquivo `config/fortigate_proxy.crt` **não deve ser commitado**, deve está no `.gitignore`.

