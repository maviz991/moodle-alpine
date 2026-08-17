# Reset + Setup (para quem já tentou antes e falhou)

> Se você já mexeu em certificado manualmente, comece pela PARTE 1.
> Se é máquina nova, pule direto para a PARTE 2.

**Não é mais necessário pedir o certificado para um colega.** O script extrai a CA
ao vivo do próprio proxy.

---

## PARTE 1 — Limpeza do que foi feito à mão

### 1.1 Remove certificados antigos/errados

```bash
sudo rm -f /usr/local/share/ca-certificates/fortigate*.crt \
           /usr/local/share/ca-certificates/cdhu*.crt
sudo rm -f /tmp/*.crt /tmp/*.pem
sudo update-ca-certificates --fresh
```

> A CA `O=Fortinet, CN=FG180FTK23901473` que circulou entre a equipe **não é a CA
> em uso hoje**. Instalar ela não resolve nada — por isso o build continuava falhando.

### 1.2 Remove config de proxy antiga do Docker

```bash
sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf
rm -f ~/.docker/config.json
sudo systemctl daemon-reload
```

### 1.3 Limpa o cache de build

```bash
docker builder prune -af
docker system prune -f
```

---

## PARTE 2 — Setup automático

### 2.1 Vá para o projeto no WSL

```bash
cd /mnt/c/Users/$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/Repositorio/Moodle/docker/moodle_alpine2
```

Se esse caminho não existir, use o seu:

```bash
cd /mnt/c/Users/<seu-usuario>/Repositorio/Moodle/docker/moodle_alpine2
```

### 2.2 Rode o setup

```bash
sudo bash scripts/setup-wsl-proxy.sh
```

O script faz, em ordem:

1. testa se `10.71.48.17:8080` está acessível
2. extrai a cadeia de certificados ao vivo do proxy
3. salva as CAs em `config/ca/`
4. instala no trust store do WSL (`update-ca-certificates`)
5. configura o proxy do **Docker daemon** (systemd drop-in)
6. corrige a variável `http_proxy=http://PROXY:8080` herdada do Windows
7. reinicia o daemon e testa `docker pull hello-world`

Ele só termina com sucesso se o `docker pull` funcionar de verdade.

### 2.3 Abra um shell NOVO

Necessário para pegar o `/etc/profile.d/zz-cdhu-proxy.sh`:

```bash
exit
```

E abra o WSL de novo.

---

## PARTE 3 — Build

```bash
cd /mnt/c/Users/<seu-usuario>/Repositorio/Moodle/docker/moodle_alpine2

# imagem básica (dev)
make build

# imagem com plugins (produção)
make build-plugins
```

Ou via compose:

```bash
cp .env.example .env      # edite as credenciais
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

Acesse: http://localhost:8080

---

## Fora da rede da CDHU (home office sem VPN)

O proxy fica inacessível, mas o build funciona **sem** ele:

```bash
make build BUILD_PROXY=
```

Ou no `.env`, deixe `BUILD_PROXY=` vazio.

As CAs em `config/ca/` continuam sendo instaladas na imagem — isso é inofensivo.

---

## Troubleshooting

| Sintoma | O que fazer |
|---|---|
| `Proxy 10.71.48.17:8080 inacessivel` | Está na rede da CDHU? VPN ligada? Se não, use `make build BUILD_PROXY=` |
| `context deadline exceeded` no pull | O daemon não pegou o proxy — `sudo systemctl restart docker` e confira `docker info \| grep -i proxy` |
| `could not resolve proxy: PROXY` | Você não abriu um shell novo depois do script (PARTE 2.3) |
| `x509: certificate signed by unknown authority` | `grep -c cdhu /etc/ssl/certs/ca-certificates.crt` — se der 0, rode o script de novo |
| Build trava em `apk update` / `fetch` | O proxy não chegou no build. Confira se `make` está passando `$(PROXY_ARGS)` |
| `docker: command not found` | dockerd não instalado no WSL — instale o Docker Engine na distro |
| `permission denied` no docker | `sudo usermod -aG docker $USER` e reabra o shell |

Detalhes técnicos do porquê de cada passo: [SETUP-PROXY-CERT.md](SETUP-PROXY-CERT.md)
