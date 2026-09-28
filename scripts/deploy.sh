#!/usr/bin/env bash
set -euo pipefail

# Deploy script idempotente para ufla-devops-shop
# Executa numa máquina limpa e deixa a aplicação no ar
# Pode ser rodado várias vezes sem quebrar nada

echo "=== Iniciando deploy da aplicação ufla-devops-shop ==="

# 1. Criar usuário de sistema se não existir
echo "Verificando usuário ufla-shop..."
if id ufla-shop &>/dev/null; then
    echo "  ✓ Usuário ufla-shop já existe"
else
    echo "  → Criando usuário ufla-shop..."
    sudo useradd --system --home-dir /opt/ufla-shop --shell /bin/bash ufla-shop
    echo "  ✓ Usuário criado"
fi

# 2. Criar diretório da aplicação se não existir
echo "Preparando diretório /opt/ufla-shop..."
if [ ! -d /opt/ufla-shop ]; then
    echo "  → Criando diretório..."
    sudo mkdir -p /opt/ufla-shop
    sudo chown ufla-shop:ufla-shop /opt/ufla-shop
fi

# 3. Copiar código para /opt/ufla-shop
echo "Sincronizando código..."
sudo rsync -av --delete \
    --exclude='.git' \
    --exclude='.venv' \
    --exclude='__pycache__' \
    --exclude='.pytest_cache' \
    --exclude='*.pem' \
    --exclude='*.key' \
    . /opt/ufla-shop/
sudo chown -R ufla-shop:ufla-shop /opt/ufla-shop

# 4. Criar arquivo de configuração se não existir (com senha aleatória)
echo "Configurando variáveis de ambiente..."
ENV_FILE="/etc/ufla-shop.env"
ENV_EXAMPLE="/etc/ufla-shop.env.example"

# Copiar exemplo se não existir
if [ ! -f "$ENV_EXAMPLE" ]; then
    sudo cp /opt/ufla-shop/systemd/ufla-shop.env.example "$ENV_EXAMPLE"
fi

# Criar arquivo de produção a partir do exemplo se não existir
if [ ! -f "$ENV_FILE" ]; then
    echo "  → Criando $ENV_FILE com senha aleatória..."
    DB_PASSWORD=$(openssl rand -hex 16)
    sudo sed "s/CHANGE-ME/${DB_PASSWORD}/" "$ENV_EXAMPLE" | sudo tee "$ENV_FILE" > /dev/null
    sudo chmod 600 "$ENV_FILE"
    echo "  ✓ Arquivo criado com senha: $DB_PASSWORD"
else
    echo "  ✓ $ENV_FILE já existe"
fi

# 5. Criar venv e instalar dependências
echo "Criando venv e instalando dependências..."
if [ ! -f /opt/ufla-shop/.venv/bin/python ]; then
    echo "  → Criando venv..."
    cd /opt/ufla-shop
    sudo -u ufla-shop python3 -m venv .venv
    sudo -u ufla-shop .venv/bin/pip install -q -U pip setuptools wheel
fi

echo "  → Instalando dependências..."
cd /opt/ufla-shop
sudo -u ufla-shop .venv/bin/pip install -q -r requirements.txt
echo "  ✓ Dependências instaladas"

# 6. Instalar units do systemd
echo "Instalando units do systemd..."
sudo cp /opt/ufla-shop/systemd/ufla-shop.service /etc/systemd/system/
sudo cp /opt/ufla-shop/systemd/ufla-shop-backup.service /etc/systemd/system/
sudo cp /opt/ufla-shop/systemd/ufla-shop-backup.timer /etc/systemd/system/
echo "  ✓ Units instaladas"

# 7. Reload, habilitar e iniciar o serviço
echo "Ativando serviço..."
sudo systemctl daemon-reload
sudo systemctl enable ufla-shop.service
sudo systemctl restart ufla-shop.service
sudo systemctl enable ufla-shop-backup.timer
sudo systemctl restart ufla-shop-backup.timer
echo "  ✓ Serviço ativo"

# 8. Criar diretório de backups
echo "Preparando backups..."
if [ ! -d /var/backups/ufla-shop ]; then
    echo "  → Criando diretório de backups..."
    sudo mkdir -p /var/backups/ufla-shop
    sudo chown ufla-shop:ufla-shop /var/backups/ufla-shop
fi

# 8.5. Instalar e configurar Nginx
echo "Configurando Nginx..."
if ! command -v nginx &> /dev/null; then
    echo "  → Instalando Nginx..."
    sudo apt install -y nginx
fi

# Criar diretório para certificados
sudo mkdir -p /etc/nginx/certs

# Gerar certificado autoassinado se não existir
if [ ! -f /etc/nginx/certs/loja.crt ]; then
    echo "  → Gerando certificado autoassinado..."
    sudo openssl req -x509 -newkey rsa:2048 -keyout /etc/nginx/certs/loja.key \
        -out /etc/nginx/certs/loja.crt -days 365 -nodes \
        -subj "/C=BR/ST=MG/L=Lavras/O=UFLA/CN=localhost"
    echo "  ✓ Certificado gerado"
fi

# Copiar configuração do Nginx
echo "  → Instalando configuração do Nginx..."
sudo cp /opt/ufla-shop/nginx/loja.conf /etc/nginx/sites-available/
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/loja.conf /etc/nginx/sites-enabled/loja.conf

# Testar configuração do Nginx
if sudo nginx -t &>/dev/null; then
    echo "  ✓ Configuração do Nginx validada"
    sudo systemctl enable nginx
    sudo systemctl restart nginx
else
    echo "  ⚠ Erro na configuração do Nginx. Verifique /etc/nginx/sites-available/loja.conf"
    exit 1
fi

# 9. Healthcheck: consultar /ready até 10 vezes, 1s de intervalo
echo ""
echo "Aguardando aplicação estar pronta..."
max_attempts=10
attempt=0
success=false

while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    echo -n "  Tentativa $attempt/$max_attempts... "
    
    if curl -s http://localhost:8000/ready | grep -q '"banco":"ok"'; then
        echo "✓"
        success=true
        break
    else
        echo "aguardando..."
        sleep 1
    fi
done

echo ""
if [ "$success" = true ]; then
    echo "=== ✅ Deploy concluído com sucesso ==="
    echo ""
    echo "Próximas ações:"
    echo "  • Verificar status: sudo systemctl status ufla-shop"
    echo "  • Ver logs: sudo journalctl -u ufla-shop -n 50 -f"
    echo "  • Testar: curl -s http://localhost:8000/ready | jq ."
    exit 0
else
    echo "=== ❌ Deploy falhou ==="
    echo "A aplicação não respondeu após $max_attempts tentativas."
    echo ""
    echo "Debugar:"
    echo "  • sudo journalctl -u ufla-shop -n 50"
    echo "  • sudo systemctl status ufla-shop"
    exit 1
fi