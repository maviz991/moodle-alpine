# Reset + Setup (para quem já tentou antes)

Execute na ordem. Não pule passos.

---

## PARTE 1 — Limpeza

### 1.1 Remove certs antigos do /tmp

```bash
sudo rm -f /tmp/*.crt /tmp/*.pem
ls /tmp/*.crt 2>/dev/null || echo "limpo"
```

### 1.2 Remove certs antigos do store do sistema

```bash
sudo rm -f /usr/local/share/ca-certificates/*.crt
ls /usr/local/share/ca-certificates/
```

> Tem que ficar vazio. Se reaparecer, ignore — só não adicione novos por enquanto.

### 1.3 Limpa build cache do Docker

```bash
docker builder prune -af
docker system prune -f
```

---

## PARTE 2 — Instalar o certificado certo

### 2.1 Receba o arquivo fortigate_proxy.crt

Peça pro colega mandar o arquivo `config/fortigate_proxy.crt` do projeto dele.

Salve em qualquer lugar no Windows (ex: `Downloads`).

### 2.2 Copie pelo Windows Explorer para o projeto

Destino:
```
C:\Users\<seu-usuario>\moodle_alpine2\config\fortigate_proxy.crt
```

**O nome tem que ser exatamente `fortigate_proxy.crt`.**

### 2.3 Instale no sistema WSL

```bash
sudo cp "/mnt/c/Users/$(whoami | cut -d'\' -f2)/moodle_alpine2/config/fortigate_proxy.crt" \
        /usr/local/share/ca-certificates/fortigate-ca.crt

sudo update-ca-certificates
```

Saída esperada:
```
1 added, 0 removed; done.
```

> Se aparecer `0 added`, o arquivo está incorreto ou vazio. Verifique com:
> ```bash
> openssl x509 -in /usr/local/share/ca-certificates/fortigate-ca.crt -noout -subject
> ```
> Tem que mostrar `O=Fortinet`.

---

## PARTE 3 — Reiniciar e testar

### 3.1 Feche o WSL (no PowerShell do Windows)

```powershell
wsl --shutdown
```

### 3.2 Abra o WSL novamente e teste o Docker

```bash
docker pull hello-world
```

Tem que baixar sem erro de SSL.

### 3.3 Faça o build

```bash
cd "/mnt/c/Users/$(whoami | cut -d'\' -f2)/moodle_alpine2"
docker build -f Dockerfile -t moodle-dev:test .
```

---

## Troubleshooting

| Sintoma | O que fazer |
|---|---|
| `1 added` mas docker ainda falha | Fez `wsl --shutdown` antes de testar? |
| `0 added` no update-ca-certificates | Arquivo vazio ou inválido — repita o passo 2.3 |
| `x509: certificate signed by unknown authority` | CA não entrou no bundle — verifique saída do `grep -c "Fortinet" /etc/ssl/certs/ca-certificates.crt` |
| `COPY failed: config/fortigate_proxy.crt not found` | Arquivo não está em `config/` do projeto |
