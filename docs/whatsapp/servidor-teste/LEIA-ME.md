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
2. **Baixe o código do WuzAPI** para dentro da pasta `servidor-teste`, com o nome `wuzapi-src` (o Docker do Windows não aceita endereço do Git como origem do build):
   - **Windows (PowerShell), sem precisar de Git:**
     ```powershell
     Invoke-WebRequest https://github.com/asternic/wuzapi/archive/refs/heads/main.zip -OutFile wuzapi.zip
     Expand-Archive wuzapi.zip -DestinationPath .
     Rename-Item wuzapi-main wuzapi-src
     Remove-Item wuzapi.zip
     dir wuzapi-src\Dockerfile   # tem que listar o arquivo
     ```
   - Com Git: `git clone https://github.com/asternic/wuzapi.git wuzapi-src`
3. **Gere os segredos**, dentro da pasta `docs/whatsapp/servidor-teste`:
   - **Windows (PowerShell):** `powershell -ExecutionPolicy Bypass -File .\gerar-env.ps1`
   - Linux, Mac ou Git Bash/WSL: `./gerar-env.sh`

   Ele cria o `.env` (ignorado pelo Git) e mostra **uma vez** o `WUZAPI_ADMIN_TOKEN`. Copie-o.
4. Suba tudo:
   ```bash
   docker compose up -d --build
   docker compose ps            # wuzapi, db e tunel em "running"
   docker compose logs wuzapi   # procure por erros
   ```
5. **Teste local primeiro** (sem o Taskfull): abra no navegador `http://localhost:8080/dashboard`. Se a página do WuzAPI aparecer, o servidor está de pé. (Pede o token de admin; é o do passo 3.)
6. Pegue o endereço público do túnel:
   - Windows PowerShell: `docker compose logs tunel | Select-String trycloudflare`
   - Linux, Mac ou Git Bash: `docker compose logs tunel | grep trycloudflare`

   Aparece algo como `https://palavras-aleatorias.trycloudflare.com`. Esse é o `WUZAPI_URL`.
7. No Supabase (projeto `painel-workspaces`) → **Edge Functions → Secrets**: crie `WUZAPI_URL` (o endereço do passo 6, sem barra no fim) e `WUZAPI_ADMIN_TOKEN` (o do passo 3). **Não cole o token no chat.**
8. No Taskfull (usuário master): aba **WhatsApp** → aceitar o aviso → **Conectar WhatsApp** → ler o QR no celular (*WhatsApp → Aparelhos conectados → Conectar um aparelho*; aparece como "Taskfull") → enviar uma mensagem **para o seu próprio número** e uma programada para daqui a 2 minutos.

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

## Ligar com um clique e ligar sozinho (2026-10-25)
- **`iniciar.ps1`**: botão direito → "Executar com o PowerShell". Abre o Docker Desktop se estiver fechado, sobe os contêineres (`docker compose up -d`), testa `http://127.0.0.1:8080/dashboard` e confere/liga o Tailscale Funnel na porta 8080. Não apaga nada e não mostra segredos. **Não testado em Windows real.**
- **Ligar sozinho quando o computador ligar:** (1) Docker Desktop → Settings → General → **Start Docker Desktop when you sign in** (os contêineres já têm `restart: unless-stopped` e voltam com o Docker); (2) Tailscale já roda como serviço; (3) em Configurações do Windows, desligue a suspensão automática se o computador ficar ligado só para isso. Sem (1), depois de reiniciar o PC o WuzAPI fica fora do ar e o Taskfull mostra **HTTP 502**.

## Botão "Ligar servidor" e agente no PC (2026-10-25)
No Taskfull (conta master) → aba WhatsApp → **🔌 Agente no PC**. **Não testado no Windows real.**
1. **Gerar chave do agente** (aparece uma vez). 2. No PC onde o Docker roda, dentro desta pasta: `powershell -ExecutionPolicy Bypass -File .\instalar-agente.ps1` e cole a chave. 3. Em 1 a 2 minutos a tela mostra "Agente ativo" e a hora em que o PC ligou. 4. **▶ Ligar servidor** pede ao agente para rodar o `iniciar.ps1` (abre o Docker Desktop e sobe os contêineres); o resultado volta para a tela.
- **Segurança:** o agente só faz conexões de saída (nada entra no PC) e só sabe rodar o `iniciar.ps1` desta pasta; o "pedido" é um simples sim/não, nunca um comando. A chave fica só em `%LOCALAPPDATA%\TaskfullAgente\config.json` (só o seu usuário lê) e, no banco, só o hash.
- **Limites:** precisa de **alguém logado no Windows** (o Docker Desktop só abre numa sessão de usuário), e de PC ligado, sem suspensão e com internet. Não mova esta pasta depois de instalar. Remover: `.\instalar-agente.ps1 -Remover`.
- Banco: tabela `servidor_agente` e funções `master_agente_gerar_chave`, `master_pedir_ligar`, `master_agente_estado` (só master), `agente_sinal` e `agente_resultado` (chamadas pelo agente com a chave).

## Subir sozinho todo dia (PC desligado à noite) (2026-10-27)
Receita para quem desliga o computador à noite e liga de manhã (feita para o teste na máquina pessoal; num servidor na nuvem nada disso é preciso):
1. **Contêineres com `restart: always`** (já no `docker-compose.yml`): voltam sozinhos sempre que o Docker sobe, mesmo depois de um desligamento normal do Windows. Depois de atualizar a pasta, rode uma vez `docker compose up -d` para valer.
2. **Docker Desktop abrindo sozinho:** Docker Desktop → Settings → General → **Start Docker Desktop when you sign in**.
3. **Entrar no Windows sem digitar senha (opcional):** o Docker Desktop só sobe depois que alguém entra no Windows. Com `netplwiz` dá para ativar o login automático. Só vale se o computador fica em lugar seguro (quem liga o PC entra direto).
4. **`instalar-inicio-automatico.ps1`** (não testado no Windows): cria a tarefa agendada que, ao entrar no Windows e depois a cada 15 min, roda o `iniciar.ps1` (abre o Docker se estiver fechado e sobe o que estiver parado). Remover: `-Remover`.
5. **Ligar o PC sozinho de manhã (opcional):** na BIOS/UEFI, opção "RTC Alarm / Wake on Alarm / Power on by RTC" (o nome varia). Com isso + login automático, o servidor sobe sem ninguém tocar.
6. **O Tailscale** já roda como serviço do Windows e mantém o Funnel (`tailscale funnel --bg 8080` fica gravado).
- As sessões do WhatsApp ficam gravadas no volume do banco do Docker: depois de religar, as pessoas continuam conectadas (só precisam ler o QR de novo se o WhatsApp as derrubar).
- Mensagens programadas para a noite esperam o servidor voltar (até 24 h) e saem na manhã seguinte.

## Painel com botões no PC (2026-10-28)
**`painel.ps1`** abre uma janela com botões: **Ver situação**, **Ligar tudo**, **Refazer Funnel**, **Reiniciar Tailscale**, **Reiniciar WuzAPI**, **Ver logs do WuzAPI** e **Endereço do túnel** (o `trycloudflare.com` do plano B). Abrir: botão direito → "Executar com o PowerShell" (pede permissão de administrador). Atalho na área de trabalho: `powershell -ExecutionPolicy Bypass -File .\painel.ps1 -CriarAtalho`. Só mostra e liga o que já existe neste PC (não abre porta, não lê o `.env`, esconde sequências longas nos logs). **Não testado no Windows real**: se algum botão errar, o texto aparece na própria janela; me mande.
