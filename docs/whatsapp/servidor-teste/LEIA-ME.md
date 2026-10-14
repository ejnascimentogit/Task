# Teste do WuzAPI num Codespace (nuvem, grátis)

Objetivo: ter um servidor do WuzAPI no ar **por algumas horas**, para testar o WhatsApp do Taskfull com o seu número. **Nada fica na máquina da empresa**: tudo roda na nuvem do GitHub, na sua conta pessoal.

> Este arquivo e o `docker-compose.yml` foram escritos mas **ainda não foram executados**: o primeiro teste real é o seu. Se algo falhar, copie a mensagem de erro do terminal e leve para o Claude.

## Passo a passo

1. **Abrir o Codespace.** No GitHub, repositório `ejnascimentogit/Task` → botão verde **Code** → aba **Codespaces** → **Create codespace on branch…** e escolha a branch `claude/optimistic-pasteur-62v455` (ou `master`, depois que a tela do WhatsApp for para lá). A máquina de 2 núcleos serve. Use **a sua conta pessoal** do GitHub.
2. **Gerar os segredos.** No terminal do Codespace:
   ```bash
   cd docs/whatsapp/servidor-teste
   ./gerar-env.sh
   ```
   Ele cria o `.env` (ignorado pelo Git) e mostra **uma vez** o `WUZAPI_ADMIN_TOKEN`. Copie-o.
3. **Subir o servidor** (a primeira vez compila o WuzAPI e leva alguns minutos):
   ```bash
   docker compose up -d --build
   docker compose ps          # os dois (wuzapi e db) devem aparecer como "running"/"healthy"
   docker compose logs -f wuzapi   # Ctrl+C para sair; procure por erros
   ```
4. **Liberar a porta.** Aba **Ports** (Portas) do Codespace → linha da porta **8080** → botão direito → **Port Visibility → Public**. Copie a URL dela (algo como `https://nome-do-codespace-8080.app.github.dev`).
   - Por ser pública, qualquer pessoa com a URL consegue **tentar** falar com o servidor; sem os tokens, as chamadas são recusadas. Por isso o token de admin é longo e aleatório.
5. **Colocar os segredos no Supabase** (painel, projeto `painel-workspaces`): **Edge Functions → Secrets**:
   - `WUZAPI_URL` = a URL da porta 8080 (sem barra no fim)
   - `WUZAPI_ADMIN_TOKEN` = o token do passo 2
6. **Testar no Taskfull** (com o seu usuário master): aba **WhatsApp** → aceitar o aviso → **Conectar WhatsApp** → ler o QR no celular (*WhatsApp → Aparelhos conectados → Conectar um aparelho*; o aparelho aparece como "Taskfull") → enviar uma mensagem **para o seu próprio número** e uma programada para daqui a 2 minutos.
7. **Ao terminar:** no GitHub → Codespaces → "…" → **Stop codespace** (ou **Delete**, que apaga também as sessões). Remova os dois segredos do Supabase se não for continuar.

## O que esperar e cuidados

- **O Codespace desliga sozinho** depois de 30 minutos sem você usar o editor. Ao voltar, reabra-o e rode `docker compose up -d` na mesma pasta. As sessões ficam guardadas no volume do PostgreSQL enquanto o Codespace existir, mas **não** é um servidor para deixar ligado (para isso: Google Cloud e2-micro, ver `SERVIDOR-WUZAPI.md`).
- `WUZAPI_AUTO_PRESENCE=unavailable` (já no `.env` gerado) evita que o WuzAPI conectado faça o seu celular parar de receber notificações do WhatsApp.
- Nunca coloque o conteúdo do `.env` em chat, e-mail ou arquivo do repositório. Se vazar, rode `rm .env && ./gerar-env.sh`, `docker compose down -v` e suba de novo (todos os QR precisam ser lidos de novo).
- **Pode falhar no primeiro teste** (os nomes dos cabeçalhos da API do WuzAPI são inconsistentes na documentação). Veja a seção 6 do `SERVIDOR-WUZAPI.md`.
- O número usado é seu e a conexão é **não oficial**: envie só para você mesmo no primeiro teste.
