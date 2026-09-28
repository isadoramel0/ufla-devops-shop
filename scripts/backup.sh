#!/usr/bin/env bash
set -euo pipefail

# backup.sh — dump datado do banco `loja` com rotacao (mantem os 7 mais recentes).
#
# Rodado pelo timer systemd ufla-shop-backup.timer (diario, 03:00) ou na mao:
#   sudo /opt/ufla-shop/scripts/backup.sh
#
# O pipefail garante que, se o pg_dump falhar, o script tambem falha (o | nao
# engole o erro).

ENV_FILE="/etc/ufla-shop.env"
BACKUP_DIR="/var/backups/ufla-shop"

# URL do banco: ja no ambiente (via EnvironmentFile do systemd) ou lida do
# arquivo de segredos. Nunca a senha em texto no script.
if [[ -z "${DATABASE_URL:-}" && -f "$ENV_FILE" ]]; then
  DATABASE_URL="$(grep -E '^DATABASE_URL=' "$ENV_FILE" | head -n1 | cut -d= -f2-)"
fi
: "${DATABASE_URL:?DATABASE_URL nao definida — verifique /etc/ufla-shop.env}"

mkdir -p "$BACKUP_DIR"

STAMP="$(date +%Y-%m-%d-%H%M%S)"
DEST="$BACKUP_DIR/loja-${STAMP}.sql.gz"

# pg_dump | gzip — se o pg_dump falhar, o pipefail derruba o script.
pg_dump "$DATABASE_URL" | gzip > "$DEST"

# Rotacao: apaga tudo alem dos 7 mais recentes.
ls -1t "$BACKUP_DIR"/loja-*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm -f

TAMANHO="$(stat -c%s "$DEST")"
logger -t backup "backup gerado: $DEST ($TAMANHO bytes)"
echo "$DEST ($TAMANHO bytes)"