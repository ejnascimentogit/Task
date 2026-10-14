#!/usr/bin/env bash
# Diagnóstico do servidor de teste do WuzAPI (Linux, Mac, Git Bash/WSL). SOMENTE LEITURA: não altera nada.
# Junta o essencial para você colar no chat com o Claude. NÃO imprime o .env; esconde sequências longas de letras/números
# (tokens, chaves) e o endereço do túnel. Mesmo assim, dê uma olhada no arquivo antes de colar.
cd "$(dirname "$0")"
esconder() { sed -E 's/[0-9a-fA-F]{32,}/[SEGREDO-OCULTO]/g; s#https://[a-z0-9-]+\.trycloudflare\.com#https://[endereco-do-tunel]#g'; }
secao() { printf '\n===== %s =====\n' "$1"; shift; "$@" 2>&1 | sed -e 's/[[:space:]]*$//'; }
{
  echo "Diagnostico em $(date '+%Y-%m-%d %H:%M:%S')"
  secao 'Docker' bash -c 'docker --version; docker compose version'
  secao 'Conteineres (docker compose ps -a)' docker compose ps -a
  secao 'Memoria e CPU agora (docker stats)' docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}'
  secao 'wuzapi: ultimas 40 linhas' docker compose logs --no-color --tail 40 wuzapi
  secao 'db: ultimas 15 linhas' docker compose logs --no-color --tail 15 db
  secao 'tunel: ultimas 15 linhas' docker compose logs --no-color --tail 15 tunel
  secao 'Porta local responde? (http://localhost:8080/dashboard)' bash -c 'curl -s -o /dev/null -m 5 -w "HTTP %{http_code}\n" http://localhost:8080/dashboard || echo "sem resposta"'
  secao '.env existe?' bash -c '[ -f .env ] && echo "sim (conteudo NAO mostrado)" || echo "nao"'
} | esconder | tee diagnostico.txt
printf '\n--- Salvo em: %s/diagnostico.txt (confira antes de colar no chat) ---\n' "$(pwd)"
