# Atividade 3 — Automatizar de Verdade

Entrega da Atividade 3 da disciplina DevOps na Prática (DCC/UFLA).

**Autor:** Isadora Gomes Melo Cunha (@isadoramel0)

## Deploy como serviço Linux com systemd, backup diário e Nginx com TLS

### a) Como rodar o deploy numa máquina limpa

```bash
# Clonar o repositório
git clone  git@github.com:isadoramel0/ufla-devops-shop.git
cd ufla-devops-shop

# Garantir que PostgreSQL e Redis estão rodando
sudo systemctl start postgresql
sudo systemctl start redis-server

# Executar o deploy
sudo bash scripts/deploy.sh
```

O script é idempotente: pode ser rodado várias vezes sem quebrar nem duplicar nada.

---

### b) Restart=on-failure funcionando

Ao derrubar o processo, o systemd reinicia automaticamente em 5 segundos:

```bash
● ufla-shop.service - ufla-devops-shop - API da loja virtual
     Loaded: loaded (/etc/systemd/system/ufla-shop.service; enabled; preset: enabled)
     Active: active (running) since Sun 2026-09-27 21:46:16 -03; 34s ago
   Main PID: 15516 (uvicorn)
      Tasks: 1 (limit: 7099)
     Memory: 42.5M (peak: 42.7M)
        CPU: 799ms
   CGroup: /system.slice/ufla-shop.service
             └─15516 /opt/ufla-shop/.venv/bin/python3 /opt/ufla-shop/.venv/bin/uvicorn app:api ->

Sep 27 21:46:16 SAMSUNGBOOK-ISA systemd[1]: ufla-shop.service: Scheduled restart job, restart co>
Sep 27 21:46:16 SAMSUNGBOOK-ISA systemd[1]: Started ufla-shop.service - ufla-devops-shop - API d>
Sep 27 21:46:16 SAMSUNGBOOK-ISA uvicorn[15516]: INFO:     Started server process [15516]
Sep 27 21:46:16 SAMSUNGBOOK-ISA uvicorn[15516]: INFO:     Waiting for application startup.
Sep 27 21:46:16 SAMSUNGBOOK-ISA uvicorn[15516]: 2026-09-27 21:39:10,470 INFO loja: ufla-devops-s>
Sep 27 21:46:16 SAMSUNGBOOK-ISA uvicorn[15516]: 2026-09-27 21:46:16,948 INFO loja.banco: banco p>
Sep 27 21:46:16 SAMSUNGBOOK-ISA uvicorn[15516]: INFO:     Application startup complete.
```

Note que o PID mudou de 13012 para 15516 e há a mensagem "Scheduled restart job".

---

### c) Nginx com TLS e redirecionamento HTTP → HTTPS

**Teste de redirecionamento HTTP → HTTPS (HTTP/1.1 301):**
```bash
$ curl -I http://localhost
HTTP/1.1 301 Moved Permanently
Server: nginx/1.24.0 (Ubuntu)
Date: Mon, 28 Sep 2026 00:44:42 GMT
Content-Type: text/html
Content-Length: 178
Connection: keep-alive
Location: https://localhost/
```

**Teste de HTTPS (HTTP/2 200):**
```bash
$ curl -kI https://localhost
HTTP/2 405 
server: nginx/1.24.0 (Ubuntu)
date: Mon, 28 Sep 2026 00:44:54 GMT
content-type: application/json
content-length: 31
allow: GET
```

(A resposta 405 é porque HEAD em / não é suportado; GET em / funciona normalmente)

---

### d) Backup com rotação (3 execuções)

```bash
$ ls -lah /var/backups/ufla-shop/
total 20K
drwxr-xr-x 2 ufla-shop ufla-shop 4.0K Sep 27 21:50 .
drwxr-xr-x 3 root      root      4.0K Sep 27 21:39 ..
-rw-r--r-- 1 root      root      1.6K Sep 27 21:47 loja-2026-09-27-2147.sql.gz
-rw-r--r-- 1 root      root      1.6K Sep 27 21:48 loja-2026-09-27-2148.sql.gz
-rw-r--r-- 1 root      root      1.6K Sep 27 21:50 loja-2026-09-27-2150.sql.gz
```

Arquivos com timestamp único, comprimidos com gzip. A rotação mantém os 7 mais recentes.

---

### e) Idempotência do deploy.sh (segunda execução)

**Primeira execução:** cria tudo do zero.

**Segunda execução:**
```bash
=== Iniciando deploy da aplicação ufla-devops-shop ===
Verificando usuário ufla-shop...
  ✓ Usuário ufla-shop já existe
Preparando diretório /opt/ufla-shop...
Sincronizando código...
[... rsync sincroniza, idempotente ...]
Configurando variáveis de ambiente...
  ✓ /etc/ufla-shop.env já existe
Criando venv e instalando dependências...
  → Instalando dependências...
  ✓ Dependências instaladas
Instalando units do systemd...
  ✓ Units instaladas
Ativando serviço...
  ✓ Serviço ativo
Preparando backups...
Configurando Nginx...
  → Instalando configuração do Nginx...
  ✓ Configuração do Nginx validada
[...]
Aguardando aplicação estar pronta...
  Tentativa 1/10... ✓

=== ✅ Deploy concluído com sucesso ===
```

Nada foi duplicado, nenhum erro, tudo reconhecido como já existente.
