# Servidor de teste do WuzAPI (WhatsApp)

Objetivo: ter um servidor do WuzAPI no ar para testar o WhatsApp do Taskfull com o seu número. Hoje ele roda **na sua máquina pessoal com Docker** (ou num Codespace). Quando o produto evoluir e você alugar uma máquina na nuvem, **estes mesmos arquivos** sobem lá do mesmo jeito (`git clone` e `docker compose up -d`).

> Regra do projeto: **nada disto roda nem fica na máquina da empresa.** Só na sua máquina pessoal ou na nuvem.
> Estes arquivos foram escritos mas **ainda não foram executados**: o primeiro teste real é o seu. Se algo falhar, copie a mensagem de erro do terminal e leve para o Claude.

## O que sobe

- `wuzapi`: o programa do WhatsApp (construído a partir do repositório oficial; a primeira vez compila e leva alguns minutos).
- `db`: PostgreSQL, onde ficam as sessões do WhatsApp (volume `db_data`).
- `tunel`: túnel grátis da Cloudflare, que dá um endereço HTTPS público para o Supabase alcançar o WuzAPI. A porta 8080 **não** fica aberta na sua rede; só o túnel chega nela.

## Na sua máquina pessoal

**Antes:** Docker instalado e funcionando (`docker --version` e `docker compose version` mostram versão). Máquina com 2 GB de memória livres ou mais. Ela precisa **ficar ligada e sem dormir** enquanto você testa.
- **Memória do Docker Desktop:** compilar o WuzAPI na primeira vez pede cerca de 2 GB livres dentro do Docker. Se o Docker Desktop estiver limitado a ~3,7 GB e já houver outros contêineres rodando (por exemplo `supabase-cli`), **pare-os antes** de subir (`docker stop <nome>`), ou aumente o limite em *Docker Desktop → Settings → Resources*. Se a compilação falhar com "killed" ou "out of memory", é isso.
- **Docker Desktop desatualizado:** o aviso de versão não impede o teste, mas atualizar ajuda se algo se comportar de forma estranha.
- **Porta 8080 ocupada:** se outro programa já usa a 8080, edite `WUZAPI_PORT` no `.env` (por exemplo `8081`) e use essa porta no endereço do teste local.

1. **Baixe os arquivos.** Enquanto a branch não for para a `master`, eles estão na branch `claude/optimistic-pasteur-62v455` (um `git clone` simples **não** os traz):
   - Com Git: `git clone -b claude/optimistic-pasteur-62v455 https://github.com/ejnascimentogit/Task.git`
   - Sem Git: baixe o ZIP em `https://github.com/ejnascimentogit/Task/archive/refs/heads/claude/optimistic-pasteur-62v455.zip`, extraia, e abra a pasta `docs/whatsapp/servidor-teste`.
2. **Gere os segredos**, dentro da pasta `docs/whatsapp/servidor-teste`:
   - **Windows (PowerShell):** `powershell -ExecutionPolicy Bypass -File .\gerar-env.ps1`
   - Linux, Mac ou Git Bash/WSL: `./gerar-env.sh`

   Ele cria o `.env` (ignorado pelo Git) e mostra **uma vez** o `WUZAPI_ADMIN_TOKEN`. Copie-o.
3. Suba tudo:
   ```bash
   docker compose up -d --build
   docker compose ps            # wuzapi, db e tunel em "running"
   docker compose logs wuzapi   # procure por erros
   ```
4. **Teste local primeiro** (sem o Taskfull): abra no navegador `http://localhost:8080/dashboard`. Se a página do WuzAPI aparecer, o servidor está de pé. (Pede o token de admin; é o do passo 2.)
5. Pegue o endereço público do túnel:
   - Windows PowerShell: `docker compose logs tunel | Select-String trycloudflare`
   - Linux, Mac ou Git Bash: `docker compose logs tunel | grep trycloudflare`

   Aparece algo como `https://palavras-aleatorias.trycloudflare.com`. Esse é o `WUZAPI_URL`.
6. No Supabase (projeto `painel-workspaces`) → **Edge Functions → Secrets**: crie `WUZAPI_URL` (o endereço do passo 4, sem barra no fim) e `WUZAPI_ADMIN_TOKEN` (o do passo 2). **Não cole o token no chat.**
7. No Taskfull (usuário master): aba **WhatsApp** → aceitar o aviso → **Conectar WhatsApp** → ler o QR no celular (*WhatsApp → Aparelhos conectados → Conectar um aparelho*; aparece como "Taskfull") → enviar uma mensagem **para o seu próprio número** e uma programada para daqui a 2 minutos.

## Cuidados

- **O endereço do túnel muda** sempre que o serviço `tunel` reinicia (ou a máquina reinicia). Aí rode `docker compose logs tunel | grep trycloudflare` e atualize o segredo `WUZAPI_URL`. As sessões do WhatsApp **não** se perdem (ficam no volume do banco). Para um endereço fixo é preciso um domínio na Cloudflare e um "túnel nomeado": faça isso quando for para a nuvem.
- Túnel rápido da Cloudflare é para teste, sem garantia de disponibilidade.
- `WUZAPI_AUTO_PRESENCE=unavailable` (já no `.env` gerado) evita que o WuzAPI conectado faça o seu celular parar de receber notificações do WhatsApp.
- Se a máquina dormir ou desligar, o WhatsApp do Taskfull para; ao voltar, `docker compose up -d` e confira se o endereço do túnel mudou.
- Nunca coloque o conteúdo do `.env` em chat, e-mail ou arquivo do repositório. Se vazar: `rm .env && ./gerar-env.sh`, `docker compose down -v` e suba de novo (todos os QR precisam ser lidos de novo).
- O número é seu e a conexão é **não oficial**: envie só para você mesmo no primeiro teste.
- **Parar tudo:** `docker compose down` (mantém as sessões) ou `docker compose down -v` (apaga tudo, inclusive as sessões). Depois do teste, remova os segredos do Supabase se não for continuar.

## Se algo não funcionar: diagnóstico para colar no chat

Rode (dentro desta pasta) e cole o resultado no chat com o Claude. É **somente leitura**: não altera nada, não mostra o `.env` e esconde automaticamente tokens, chaves e o endereço do túnel. Confira o arquivo `diagnostico.txt` antes de colar.
- Windows: `powershell -ExecutionPolicy Bypass -File .\diagnostico.ps1`
- Linux, Mac ou Git Bash/WSL: `./diagnostico.sh`

(O `diagnostico.ps1` não foi testado: não há PowerShell no ambiente do Claude. O `.sh` foi testado, inclusive o mascaramento.)

## Alternativa: Codespace (nuvem do GitHub, grátis)

Serve para um teste curto, sem usar a sua máquina. Abra um Codespace no repositório (conta pessoal), rode os mesmos passos 2 e 3 na pasta `docs/whatsapp/servidor-teste`, e use o endereço do túnel (passo 4) como `WUZAPI_URL`. O Codespace desliga sozinho após 30 minutos sem uso; não serve para deixar ligado.

## Quando for para a nuvem (depois)

Alugue uma VPS (cerca de US$ 4 a 6 por mês, ou a Oracle "Always Free" se estiver disponível), instale Docker e repita os passos 1 a 3. Troque o túnel rápido por um túnel nomeado com domínio próprio (endereço fixo) e atualize `WUZAPI_URL` uma vez. O restante do Taskfull não muda.
