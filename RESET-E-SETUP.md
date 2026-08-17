# Reset + Setup - fluxo novo (script automático)

> Substitui os passos manuais de certificado. Não é mais preciso pedir
> `fortigate_proxy.crt` pra ninguém - o script extrai a CA certa direto do proxy.

Execute na ordem. Não pule passos.

---

## PARTE 1 - Limpeza (só se você já tentou configurar isso à mão antes)

Se é a primeira vez na máquina, pule para a PARTE 2.

### 1.1 Remove certificados antigos/errados

```bash
sudo rm -f /usr/local/share/ca-certificates/fortigate*.crt \
           /usr/local/share/ca-certificates/cdhu*.crt
sudo rm -f /tmp/*.crt /tmp/*.pem
sudo update-ca-certificates --fresh
```

> Se você tinha instalado o `fortigate_proxy.crt` (`O=Fortinet, CN=FG180FTK...`)
> que circulava entre a equipe: essa CA **não é a que o proxy usa hoje**, por
> isso o build continuava falhando mesmo com `1 added`. O script da PARTE 2
> extrai a cadeia correta ao vivo.

### 1.2 Remove config de proxy antiga do Docker daemon

```bash
sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf
sudo systemctl daemon-reload
```

### 1.3 Limpa cache de build

```bash
docker builder prune -af
docker system prune -f
```

---

## PARTE 2 - Rodar o script de setup

### 2.1 Vá até o projeto no WSL

```bash
cd "/mnt/c/Users/$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/Repositorio/Moodle/docker/moodle_alpine2"
```

Se o caminho não bater, ajuste manualmente:

```bash
cd /mnt/c/Users/<seu-usuario>/Repositorio/Moodle/docker/moodle_alpine2
```

### 2.2 Rode o script

```bash
sudo bash scripts/setup-wsl-proxy.sh
```

Ele faz tudo sozinho:

1. testa se `10.71.48.17:8080` (proxy FortiGate) está acessível
2. extrai a cadeia de certificados **ao vivo** do proxy
3. salva as CAs em `config/ca/` (raiz + intermediária)
4. instala no trust store do WSL
5. configura o proxy do **Docker daemon** (systemd drop-in - sem isso o `docker pull` trava em `context deadline exceeded`)
6. corrige a variável `http_proxy=http://PROXY:8080` herdada do Windows (o host `PROXY` não resolve dentro do WSL)
7. reinicia o daemon e testa com `docker pull hello-world` de verdade

Só termina "concluído" se o pull realmente funcionar.

### 2.3 Abra um shell NOVO

Necessário pra pegar a correção de proxy do `/etc/profile.d/`:

```bash
exit
```

Abra o WSL de novo antes do próximo passo.

---

## PARTE 3 - Build

```bash
cd /mnt/c/Users/<seu-usuario>/Repositorio/Moodle/docker/moodle_alpine2
make build
```

Para a imagem de produção com plugins:

```bash
make build-plugins
```

---

## Fora da rede da CDHU (sem VPN)

O proxy fica inacessível - builde sem ele:

```bash
make build BUILD_PROXY=
```

---

## Troubleshooting

| Sintoma | O que fazer |
|---|---|
| `Proxy inacessivel` no script | Está na rede CDHU / VPN ligada? Senão use `make build BUILD_PROXY=` |
| `context deadline exceeded` no pull | Daemon não pegou o proxy - `sudo systemctl restart docker`, confira `docker info \| grep -i proxy` |
| `could not resolve proxy: PROXY` | Você não abriu shell novo depois do script (passo 2.3) |
| `x509: certificate signed by unknown authority` | `grep -c cdhu /etc/ssl/certs/ca-certificates.crt` - se 0, rode o script de novo |
| Build trava em `apk update` | Proxy não chegou no build - confira se o `make` está passando os `--build-arg` de proxy |

Detalhes técnicos completos (por que cada passo existe): [SETUP-PROXY-CERT.md](SETUP-PROXY-CERT.md)
Versão para repassar a um colega do zero: [RESET-E-SETUP-COLEGA.md](RESET-E-SETUP-COLEGA.md)
