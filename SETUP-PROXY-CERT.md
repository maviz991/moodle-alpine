# Setup do Proxy SSL (FortiGate CDHU) — WSL + Docker

> **Contexto:** a rede da CDHU tem um proxy FortiGate em `10.71.48.17:8080` que faz
> inspeção SSL. Sem configurar, `docker pull` e `docker build` falham.

## TL;DR

```bash
cd /mnt/c/Users/<seu-usuario>/Repositorio/Moodle/docker/moodle_alpine2
sudo bash scripts/setup-wsl-proxy.sh
```

Abra um shell **novo** e rode `make build`. Pronto.

O resto deste documento explica o que o script faz e como diagnosticar.

---

## Por que falhava

São **três** problemas independentes. Corrigir só um não resolve.

### 1. Docker daemon sem proxy → `context deadline exceeded`

O `docker pull` é feito pelo **daemon**, não pelo seu shell. O daemon não lê
`http_proxy` do seu terminal. Sem proxy configurado nele, ele tenta saída direta
para a internet — que é bloqueada — e dá timeout:

```
Error response from daemon: Get "https://registry-1.docker.io/v2/":
context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

**Correção:** systemd drop-in em `/etc/systemd/system/docker.service.d/http-proxy.conf`.

### 2. Variável `http_proxy=http://PROXY:8080` herdada do Windows

O Windows exporta essa variável para o WSL via `WSLENV`. Mas o hostname literal
`PROXY` **não resolve** dentro do WSL:

```bash
$ getent hosts PROXY
(nada)
```

Resultado: todo `curl`, `apt`, `git` e `docker build` falha com erro de DNS ou
"could not resolve proxy".

**Correção:** `/etc/profile.d/zz-cdhu-proxy.sh` reescreve para o IP real.

### 3. CA errada no trust store

A CA que estava em `config/fortigate_proxy.crt` (`O=Fortinet, CN=FG180FTK23901473`)
**não faz parte da cadeia emitida pelo proxy hoje**. Instalar ela não adianta nada.

A cadeia real é:

```
folha:          CN=*.docker.com
  emitida por:  CN=10.71.48.17, emailAddress=fortigate@cdhu.sp.gov.br   (CA intermediária)
    emitida por: DC=br, DC=gov, DC=sp, DC=cdhu, CN=cdhu-SRV-VP-009-CA   (CA raiz)
```

**Correção:** o script extrai a cadeia ao vivo do proxy e instala as CAs em
`config/ca/`, sem depender de arquivo enviado por colega.

---

## Verificação manual (se quiser conferir)

### Cadeia atual do proxy

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
  openssl s_client -proxy 10.71.48.17:8080 \
    -connect registry-1.docker.io:443 -servername registry-1.docker.io \
    -showcerts </dev/null 2>/dev/null \
  | openssl crl2pkcs7 -nocrl -certfile /dev/stdin \
  | openssl pkcs7 -print_certs -noout
```

Deve terminar em `CN=cdhu-SRV-VP-009-CA`.

### CAs instaladas no sistema

```bash
ls /usr/local/share/ca-certificates/
grep -c "cdhu" /etc/ssl/certs/ca-certificates.crt
```

### Proxy do daemon

```bash
docker info | grep -i proxy
```

Deve mostrar `HTTP Proxy: http://10.71.48.17:8080`.

### Teste de ponta a ponta

```bash
docker pull hello-world
```

---

## Como o build usa isso

O `Dockerfile` **não tem mais proxy nem cert hardcoded**. Ele:

- aceita `--build-arg HTTP_PROXY=...` (vazio por padrão — builda fora da rede sem alteração)
- instala **qualquer** `.crt` que exista em `config/ca/`; se a pasta estiver vazia,
  o build segue normalmente
- **limpa** as variáveis de proxy no final, para o container não rotear tudo pelo
  FortiGate em runtime

Fontes do proxy no build:

| Comando | De onde vem o proxy |
|---|---|
| `make build` | variável `BUILD_PROXY` do Makefile (default: `10.71.48.17:8080`) |
| `docker compose build` | `BUILD_PROXY` do arquivo `.env` |
| `docker build` direto | você passa `--build-arg HTTP_PROXY=...` |

Para buildar **fora** da rede CDHU:

```bash
make build BUILD_PROXY=
```

---

## Troubleshooting

| Sintoma | Causa | Correção |
|---|---|---|
| `context deadline exceeded` no pull | daemon sem proxy | `sudo bash scripts/setup-wsl-proxy.sh` |
| `could not resolve proxy: PROXY` | env var herdada do Windows | abra shell novo após rodar o script |
| `x509: certificate signed by unknown authority` | CA não instalada ou errada | rode o script; ele extrai a CA ao vivo |
| `tls: failed to verify certificate` | CA raiz da CDHU ausente do bundle | `grep -c cdhu /etc/ssl/certs/ca-certificates.crt` deve ser > 0 |
| Build trava em `apk update` | proxy não chegou no build | confira `docker build` com `--build-arg HTTP_PROXY=` preenchido |
| `Proxy inacessivel` no script | fora da rede / VPN desligada | conecte na rede CDHU ou builde com `BUILD_PROXY=` |
| Funciona no shell mas não no daemon | daemon não reiniciado | `sudo systemctl restart docker` |

---

## Observações

- A CA raiz `cdhu-SRV-VP-009-CA` expira em **abril/2027**; a intermediária do
  FortiGate também. Quando expirarem, rode o script de novo — ele re-extrai.
- Os arquivos em `config/ca/` são **certificados públicos** (sem chave privada) e
  ficam versionados de propósito, para o build funcionar em qualquer clone.
  O `.gitignore` tem uma exceção explícita para eles.
- Rodar o script mais de uma vez é seguro (idempotente).
