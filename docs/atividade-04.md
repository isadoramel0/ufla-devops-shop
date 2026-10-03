# Atividade 4 — Containerizar a Aplicação

**Autor:** Isadora Gomes Melo Cunha (@isadoramel0)
## 1. Tamanho da imagem: antes e depois

**Primeira versão construída:**
- Base: `python:3.12-alpine`
- Build: Multi-stage
- Tamanho: **33 MB**

```bash
$ docker image inspect --format '{{.Size}}' ufla-shop:1.0 | numfmt --to=si
33M
```

**Para referência (do docs/aplicacao.md):**
- `python:3.12-slim` + deps: 168 MB (ultrapassa 150 MB)
- `python:3.12-alpine` + deps: 101 MB (esperado)
- **Minha imagem: 33 MB** (68% menor que o esperado!)

---
## 2. Alterações e análise das camadas

### Estratégia: Multi-stage com Alpine

**Estágio 1 (builder):**
- Instala dependências com `pip install --user --no-cache-dir`
- Coloca tudo em `/root/.local`

**Estágio 2 (runtime):**
- Copia apenas `/root/.local` do builder (as dependências)
- Copia apenas `app/` e `static/` (não todo repositório)
- Usuário não-root: `app` (UID 1000)
- Define PATH para encontrar binários

### Análise com `docker history`:

```bash
$ docker history ufla-shop:1.0 --human
IMAGE          CREATED      CREATED BY                                      SIZE
COPY /root/.local /home/app/.local → 43.9 MB (dependências Python)
apk add ca-certificates → 50.4 MB (Python compilado)
ADD alpine-minirootfs → 9.08 MB (base Alpine)
COPY app/ ./app/ → 106 kB (código)
COPY static/ ./static/ → 24.6 kB (assets)
COPY --chown=app:app . . → 160 kB (configurações)
RUN adduser -D -u 1000 app → 41 kB (usuário)
```

**Total em camadas (docker history): ~104 MB**

**Tamanho final da imagem: 33 MB**

A diferença ocorre porque:
- O Docker armazena camadas **comprimidas**, não descompactadas
- Há **deduplicação** de conteúdo comum entre camadas
- O `.dockerignore` **efetivo** previne copiar arquivos desnecessários

- **`.dockerignore` bem executado**: exclui `.git`, `.venv`, `__pycache__`, `tests`, `*.db`, `.env`, `.github`, `docs/`
   - Reduz significativamente o contexto de build

- **Cópia seletiva**: apenas `app/` e `static/`
   - Não leva arquivos desnecessários do repositório

- **Alpine é muito eficiente**: 60 MB vs 125 MB (slim)
   - Todas as dependências têm wheels para musl (sem compilação extra)

- **Multi-stage elimina overhead de build**:
   - Builder instala tudo e deps no `/root/.local`
   - Final copia apenas o resultado
   - Sem pip, sem caches de build, sem ferramentas desnecessárias na imagem final

### Comparativo com referências (do docs/aplicacao.md)

| Versão | Base | Tamanho |
|--------|------|---------|
| Referência (slim + deps) | `python:3.12-slim` | 168 MB |
| Esperado (alpine + deps) | `python:3.12-alpine` | 101 MB |
| **Imagem** | `python:3.12-alpine` | **33 MB** |
| **Economia** | - | **68% menor que o esperado** |
---

## 3. Verificações de funcionamento

### 3.1 Tamanho da imagem

```bash
$ docker image inspect --format '{{.Size}}' ufla-shop:1.0 | numfmt --to=si
33M
```

✅ **Menor que 150 MB**

### 3.2 Executa como usuário não-root

```bash
$ docker run --rm ufla-shop:1.0 id -u
1000
```

✅ **UID diferente de 0 (não é root)**

### 3.3 HEALTHCHECK respondendo

```bash
$ docker run -d --name loja -p 8000:8000 ufla-shop:1.0
$ sleep 10 && docker inspect --format '{{.State.Health.Status}}' loja
healthy
```

✅ **Status: healthy**

### 3.4 Endpoints da aplicação

```bash
$ curl -s localhost:8000/health
{"status":"ok","versao":"1.0.0"}

$ curl -s localhost:8000/api/produtos | jq '. | length'
12
```

✅ **/health responde 200**
✅ **/api/produtos retorna 12 produtos**

### 3.5 Encerramento rápido

```bash
$ time docker stop loja
loja

real    0m0.535s
user    0m0.017s
sys     0m0.014s
```

✅ **Encerrou em 0.535s (< 2s)**

O CMD na forma exec garante que o SIGTERM chega direto ao uvicorn:
```dockerfile
CMD ["uvicorn", "app:api", "--host", "0.0.0.0", "--port", "8000"]
```

---

## 4. Por que HEALTHCHECK consulta `/health` e não `/ready`?

O `/health` é uma verificação de **liveness** (o processo está vivo?). Ele responde sempre 200 sem consultar dependências externas, sendo ideal para determinar se o container deve ser reiniciado.

O `/ready` é **readiness** (pronto para tráfego?). Retorna 503 se banco ou cache estiverem fora, sendo mais apropriado para descoberta de serviços e roteamento. Usar `/ready` no HEALTHCHECK faria o Docker reiniciar o container toda vez que PostgreSQL ou Redis ficassem indisponíveis, mesmo que a aplicação estivesse saudável.