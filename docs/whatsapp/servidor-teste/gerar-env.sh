#!/usr/bin/env bash
# Cria o arquivo .env com segredos aleatórios (só no Codespace; o .env é ignorado pelo Git).
set -euo pipefail
cd "$(dirname "$0")"
if [ -f .env ]; then echo "O .env já existe. Apague-o (rm .env) se quiser gerar de novo."; exit 1; fi
r() { openssl rand -hex "$1"; }
cat > .env <<ENV
WUZAPI_ADMIN_TOKEN=$(r 24)
WUZAPI_GLOBAL_ENCRYPTION_KEY=$(r 16)
WUZAPI_GLOBAL_HMAC_KEY=$(r 32)
DB_USER=wuzapi
DB_PASSWORD=$(r 16)
DB_NAME=wuzapi
DB_HOST=db
DB_PORT=5432
DB_SSLMODE=false
WUZAPI_PORT=8080
WUZAPI_ADDRESS=0.0.0.0
TZ=America/Sao_Paulo
SESSION_DEVICE_NAME=Taskfull
WUZAPI_AUTO_PRESENCE=unavailable
LOG_LEVEL=info
ENV
chmod 600 .env
echo "Pronto: .env criado."
echo
echo "Copie o valor abaixo para o segredo WUZAPI_ADMIN_TOKEN no Supabase (Edge Functions > Secrets)."
echo "Ele só aparece aqui, no seu terminal. Não cole em chat, e-mail ou arquivo do repositório:"
echo
grep '^WUZAPI_ADMIN_TOKEN=' .env | cut -d= -f2-
