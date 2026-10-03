# Stage 1: build (instala dependências)
FROM python:3.12-alpine AS builder

WORKDIR /build

COPY requirements.txt .

RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: runtime (apenas o necessário)
FROM python:3.12-alpine

# Criar usuário não-root
RUN adduser -D -u 1000 app

WORKDIR /app

COPY --from=builder /root/.local /home/app/.local

COPY app/ ./app/
COPY static/ ./static/
COPY --chown=app:app . .

USER app

ENV PATH=/home/app/.local/bin:$PATH \
    PYTHONUNBUFFERED=1

CMD ["uvicorn", "app:api", "--host", "0.0.0.0", "--port", "8000"]

# HEALTHCHECK
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health'); exit(0)"