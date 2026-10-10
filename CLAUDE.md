# Taskfull: instruções e estado do projeto

Painel pessoal/de equipe multi-workspace (tarefas, agenda, pendências, clientes/projetos). Projeto **pessoal** do Edimilson: tudo dele (código, documentação, notas, decisões) fica **neste repositório** (`ejnascimentogit/Task`). Nada do Taskfull deve ficar guardado em máquina da Intelipulse, em pasta local ou em memória de ferramenta: se for preciso guardar algo, vai pra cá.

Documentação técnica completa: `DOCUMENTACAO-TASKFULL.md` (também em `/docs` no site). Este arquivo é o resumo operacional.

## Arquivos

- `index.html`: o app inteiro (HTML/CSS/JS puro, sem build). **`deploy/public/index.html` é uma cópia idêntica e as duas sempre mudam juntas.**
- `workspace-schema.sql`: schema do banco + RLS, incluindo as migrações aplicadas (as das novidades de outubro/2026 estão no final).
- `supabase-edge-functions/buscar-ia/index.ts`: Edge Function da busca com IA. **Não publicada.**
- `supabase-edge-functions/cronograma-criar-login/index.ts`: Edge Function que cria o login do cliente no Cronograma (**publicada**).
- `deploy/public/cronograma.html`: portal do cliente, servido em `/cronograma` (arquivo próprio, não é cópia do `index.html`).
- `DOCUMENTACAO-TASKFULL.md` e `deploy/public/docs.html`: documentação (md e página `/docs`). Atualizar as duas junto com o código.
- `painel-implantacao.html`, `supabase-schema.sql`, `documentacao-gestao-implantacao.md`: o sistema de referência (Painel de Implantação), mantido aqui só como referência. Não é este app.

## Infra

- **Site:** `https://taskfull.ejnascimento1.workers.dev` (Cloudflare Workers, publica `deploy/`). Todo push na `master` publica sozinho em 1 a 2 minutos.
- **Banco:** Supabase, projeto `painel-workspaces` (ref `dubbmmjtbunzmdmfbbja`). **Não confundir com o projeto `admfullcontrolefinanceiro`** (outro sistema). RLS por `is_member(workspace_id)`/`is_admin(workspace_id)`.
- A URL e a chave **publishable/anon** ficam no topo do `<script>` do `index.html` (seguras de expor). **Nunca** colocar `service_role`, chave da Anthropic ou qualquer segredo em arquivo, no HTML ou em conversa: segredos de função ficam em Supabase → Edge Functions → Secrets.
- **Lacuna conhecida:** o e-mail padrão do Supabase só entrega para membros da organização do projeto, então confirmação de cadastro, convite e redefinição de senha não chegam para outras pessoas. A correção é configurar SMTP próprio (Brevo ou Resend). O link "Esqueci minha senha" da tela de login já existe e só passa a funcionar para todo mundo depois disso. Não desligar "Confirm email" (convites casam por e-mail e poderiam ser sequestrados).

## Como alterar e publicar

1. Ler o código atual (somente leitura): `https://raw.githubusercontent.com/ejnascimentogit/Task/master/index.html`.
2. Fazer a mudança como script (python) com `assert s.count(old) == 1` em cada trecho, aplicado **nos dois** `index.html`.
3. Validar: extrair o maior `<script>` e rodar `node --check`; `diff index.html deploy/public/index.html` tem que ficar vazio.
4. `git add`, `git commit`, `git push` na `master` (de um Codespace, não de máquina da empresa). Esperar o Cloudflare publicar (conferir com `curl` procurando o nome de uma função nova).
5. Conferir no site logado. Atualizar a documentação e este arquivo se algo relevante mudou.

Mudanças de banco: aditivas e idempotentes (`add column if not exists`, `drop function if exists` antes de recriar função), e registradas no `workspace-schema.sql`.

## Regras do projeto

- **Só incluir:** mudanças novas não removem comportamento existente sem pedido explícito.
- Nenhum recurso depende de reatividade automática: quem grava "em silêncio" precisa chamar o render do pedaço da tela que mostra aquele dado. Toda gravação checa o `error` do Supabase e avisa (`alert`).
- Regra de **união** para pessoas: o responsável sempre conta e os participantes somam por cima (nunca substituem).
- Toda consulta ao banco leva o `workspace_id`; nunca depender só da tela para proteger dado.

## Estado (2026-10-05)

Trazido do Painel de Implantação (documentado na seção 9 da documentação): Indicadores, Buscar (full-text), Lâmina (imagem/PDF), pendências com arrastar/copiar/flag da Lâmina, filtros de cliente e pessoa em Resumo/Relatório, contatos ao agendar, hora obrigatória, badge de idade, filtros de "hoje" que não congelam, botão Atualizar e corretor ortográfico PT-BR. Também em produção: Feriados & Datas (BrasilAPI + lista editável), calendário mensal, "Criado por" fixo, observação por pendência.

### Busca com IA: estrutura pronta, DESLIGADA, é a última etapa

Decisão do Edimilson: a IA só será ligada por último, depois de observar como se comporta nas duas plataformas (o Painel da Intelipulse também paga IA). A chave da Anthropic valeria para todos os workspaces, então: liga por workspace em `busca_ia_config` (só o dono do app escreve, pelo SQL Editor), limite mensal em US$ por workspace, uso em `busca_ia_uso` (gravado só pela função), e a função refaz a busca no servidor com o token de quem chamou. Passo a passo para ligar está no cabeçalho de `supabase-edge-functions/buscar-ia/index.ts`.

### Cronograma do cliente (só Gestão de Projeto), em produção desde 2026-10-05

Aba "Cronograma" (editor por projeto) + portal `/cronograma` para o cliente. Tabelas `cronograma_acessos/etapas/itens/subitens/log` (RLS: membros gerenciam, cliente só lê o próprio projeto), funções `cronograma_entidade_do_usuario`, `cronograma_meu_projeto`, `cronograma_marcar_senha_trocada`, `atualizar_item_cronograma_cliente` (único caminho de escrita do cliente: só status/baseline/data, só em item do cliente, com log) e `duplicar_cronograma`. Login do cliente criado pela Edge Function `cronograma-criar-login` (só **admin** do workspace; usuário + senha provisória aleatória mostrada uma vez; troca obrigatória no primeiro acesso; e-mail sintético `@cliente.taskfull.invalid`). Contas de cliente não criam workspace nem entram por convite, e são redirecionadas para `/cronograma`. Detalhes na seção 9.6 da documentação.

Também entraram: analista responsável (Equipe e Projeto) e previsão de entrega (só Projeto), busca dentro da nota, "Esqueci minha senha" (tela de nova senha + `redirectTo` correto) e rótulos de em aberto/concluída no Buscar.

### Decisões e pendências

- **Contato do dia por canal:** decidido deixar como está (coluna `entidades.ultimo_contato_canal` existe, sem tela).
- **Hora obrigatória:** vale nos três perfis, incluindo Pessoal (decidido).
- **SMTP próprio (Brevo ou Resend):** pendente, é o Edimilson quem configura. Sem isso, "Esqueci minha senha" e convites só chegam a membros da organização do Supabase.
- **Busca com IA:** continua desligada e é a última etapa (seção acima).
- **Repositório público:** ele contém arquivos do Painel de Implantação (referência) e a documentação. Decidir se esses arquivos saem do repositório ou se o repositório vira privado antes de guardar qualquer coisa de negócio aqui.
- Ideia separada, sem escopo: integração com Instagram.

## Dicas de teste

- Ao ler o estado pelo console, esperar o `loadWorkspaceData` terminar (variáveis como `activeWorkspace` e `atividades` só existem depois).
- Botão "Sincronizar datas comerciais" abre uma confirmação do navegador: sem confirmar, nada é gravado.
- Mudou a lista `DEFAULT_FERIADOS_COMERCIAIS`? Cada workspace precisa clicar em Sincronizar para receber as datas novas.

## Assessor pessoal (perfil Pessoal) — canal Telegram (desde 2026-10-07)

Produto pessoal do Edimilson com o sócio Ryan: um assessor que conversa pelo Telegram (WhatsApp oficial depois), cria e consulta compromissos e tarefas do perfil **Pessoal** e avisa antes de cada compromisso. O Taskfull é a memória e o painel; o assessor é uma camada em cima do perfil Pessoal (não existe perfil novo). Só funciona em workspace com `perfil_tipo = 'pessoal'`.

**Como funciona**
- Bot: `@assessor_ej_teste_bot` (teste). Conexão: Configurações → "🤖 Assessor no Telegram" → "Conectar Telegram" gera um código de 6 caracteres (vale 15 min) → a pessoa envia ao bot (ou abre `t.me/<bot>?start=<código>`).
- Edge Function `assessor-telegram` (`verify_jwt = false`): webhook do Telegram, autenticado pelo cabeçalho `X-Telegram-Bot-Api-Secret-Token`, que é um SHA-256 derivado do próprio token do bot. `GET ...?acao=configurar` registra o webhook e os comandos (e mostra um diagnóstico sem expor o token). Responde 200 na hora e processa em segundo plano (`EdgeRuntime.waitUntil`).
- IA: Claude `claude-sonnet-5-5` (constante `MODELO`, preços em `PRECO`, atualizar à mão), com cache de prompt e ferramentas: listar/criar/remarcar/concluir compromisso, listar/criar/cancelar tarefa. Regra de produto: **com dia e hora → Agenda; sem hora → tarefa em Atividades; dia sem hora → pergunta**; toda confirmação começa com "📅 Agenda:" ou "📝 Tarefa:". Botão "↩ Desfazer" em tudo que é criado.
- Histórico curto (`assessor_mensagens`, últimas 10) entra no contexto; respostas guardam no fim "[Ações executadas: ...]" (registro interno, removido do texto enviado) para o modelo não achar que inventou ações anteriores.
- Lembretes: Edge Function `assessor-lembretes` (`verify_jwt = true`), chamada a cada minuto pelo `pg_cron` (job `assessor-lembretes`, via `pg_net`, com a chave anon). RPC `assessor_lembretes_pendentes()` (só `service_role`) acha os compromissos dentro da janela `lembrete_minutos` (15/30/60/120, padrão 60) no horário de Brasília; `assessor_lembretes_enviados` evita aviso duplicado (remarcar limpa o registro).
- Privacidade: job `assessor-limpar-mensagens` apaga conversas com mais de 30 dias; "Desconectar" apaga vínculo e conversas. O navegador não tem policy de update em `assessor_vinculos`: só altera pelas RPCs `assessor_gerar_codigo`, `assessor_definir_lembrete`, `assessor_desconectar`.
- Medidor: `assessor_uso` grava tokens (entrada, saída, cache lido/gravado) e custo estimado por mensagem. Indicadores → "🤖 Uso do Assessor Pessoal" mostra mensagens do mês (com o total desde o início no rodapé), gasto do mês em US$, quanto ainda pode gastar (`assessor_vinculos.limite_mensal_usd`, padrão US$ 3) e o gasto do mês em reais com quanto ainda tem em reais (AwesomeAPI, reserva 5,5).
- Tabelas: `assessor_vinculos`, `assessor_mensagens`, `assessor_uso`, `assessor_lembretes_enviados` (schema em `workspace-schema.sql`). Código das funções em `supabase-edge-functions/assessor-telegram` e `supabase-edge-functions/assessor-lembretes` (deploy feito pelo MCP do Supabase; ao mudar, publicar de novo).

**Segredos (Supabase → Edge Functions → Secrets, nunca em arquivo)**: `TELEGRAM_BOT_TOKEN` (do @BotFather; se vazar, `/revoke` e trocar), `ANTHROPIC_API_KEY` (conta individual da Anthropic, workspace "Assessor Pessoal", chave "Assessor Pessoal - teste" até 31/12/2026, limite US$ 3/mês), `CLOUDFLARE_AI_TOKEN` (Workers AI, transcrição de áudio com Whisper), `GOOGLE_CLIENT_ID` e `GOOGLE_CLIENT_SECRET` (OAuth do Gmail, projeto Google Cloud `assessor-pessoal-511122`). A OpenAI não é usada.

**Custo medido no primeiro teste**: 8 mensagens, US$ 0,093 no total (≈ R$ 0,06 por mensagem com Sonnet e cache), abaixo da estimativa de R$ 0,10 do plano Avançado.

**Visão do produto e decisões (antes ficavam fora do repositório)**
- Documento de escopo (Claude Docs, privado): https://claude.ai/code/artifact/9520a0df-7359-4f7e-84b5-b0fbdb33be9c. Protótipo "Central de Conexões": https://claude.ai/artifact/2GrkYaxSVbCuPqY72Ps8QP.
- Planos: Básico R$ 29 (Haiku, 150 msg/mês), Avançado R$ 79 (Sonnet, 300), Hiper avançado R$ 249 (Sonnet + Opus semanal, 600), Jarvis-Full R$ 499 (Sonnet + Opus diário, 900). "Jarvis" é marca da Marvel/Disney: confirmar com advogado antes de usar comercialmente.
- Princípio: a pessoa escolhe o que é analisado (listas de permissão por fonte: contatos de WhatsApp, remetentes de e-mail; redes sociais abertas com triagem). Saúde sem diagnóstico; crise → CVV 188.
- Número do assessor: API oficial da Meta (precisa de CNPJ e verificação). Evolution/WuzAPI só para protótipo interno ou leitura opcional do WhatsApp pessoal, com consentimento.
- Teste grátis planejado: 7 dias ou 50 mensagens (nível Avançado), Telegram + e-mail; ao acabar, o bloco some dos Indicadores e aparece a tela "Escolha seu plano".
- Ideia aprovada, não feita: item "Novidades" no menu do perfil Pessoal (vídeo geral na 1ª vez, depois só as novidades; botão "Quero testar" como medida de interesse).
- Próximos passos: áudio (OpenAI), "bom dia" (clima, notícias, vídeos novos de canais favoritos), e-mail (Outlook/IMAP, depois Gmail com auditoria), WhatsApp oficial. Música e redes sociais em ondas.

## Corretor ortográfico: Web Worker e carga sob demanda (2026-10-07)
O dicionário pt-BR (~5,4 MB, Typo.js) era montado ao abrir a página e travava a tela por vários segundos. Agora roda num Web Worker (blob, `importScripts` do typo.js) e só é baixado quando a pessoa digita num campo com corretor (`atualizarOrtografia(ta, true)` no `input`); abrir página ou modal não dispara o download. O `<script>` do typo.js saiu da página. Palavras já verificadas ficam em cache (`palavrasErradasCache`). Se o worker falhar, segue sem sublinhar nada.

## Atualização automática da tela (2026-10-09)
Pedido do Edimilson: não precisar dar F5 para ver o que o assessor (Telegram) ou outra pessoa gravou. O Supabase Realtime está ligado para `agendamentos` e `atividades` (publicação `supabase_realtime`; respeita a RLS) e o Taskfull assina as mudanças do workspace aberto (`ligarAutoRefreshRealtime()`, chamada no início de `render()`, troca o canal ao trocar de workspace). Cada aviso agenda um `refreshDados()` 1,5 s depois (agrupa rajadas). Recarga de segurança a cada 2 min e ao voltar para a aba. Nunca atualiza com modal aberto ou campo em foco (`telaOcupada()`): marca `autoRefreshPendente` e aplica quando a pessoa fecha o modal ou sai do campo. Para incluir outras tabelas, adicionar à publicação e ao canal.

**Para quando formos para o mobile (anotado a pedido do Edimilson):** no app (PWA na Play Store ou nativo), manter a atualização ao voltar para o app (`visibilitychange` já cobre o PWA), mas trocar a recarga periódica por **notificação push** (avisos do assessor e mudanças importantes), para economizar bateria e dados; o Realtime só faz sentido com o app aberto. Testar o comportamento com o celular em segundo plano e sem conexão (recarregar ao reconectar).

## Assessor: áudio, busca na web e vocabulário (2026-10-09)
- **Áudio**: mensagem de voz (ou arquivo de áudio) no Telegram, até 5 min, é transcrita pelo **Cloudflare Workers AI** (`@cf/openai/whisper-large-v3-turbo`, JSON com `audio` em base64 e `language: "pt"`; reserva `@cf/openai/whisper` com corpo binário). O bot ecoa "🎤 Entendi: ..." e segue como se fosse texto. Segundos de áudio vão para `assessor_uso.audio_segundos`. A OpenAI não é usada.
- **Velocidade**: todo compromisso criado pelo assessor ganha na observação "🤖 Assessor (meio) · mensagem enviada às HH:MM:SS · gravado na agenda às HH:MM:SS (N s depois)".
- **Nomes próprios**: quando a transcrição erra um nome (ex.: "Giorgio" em vez de "JoJo's"), o modelo usa a ferramenta de servidor `web_search_20260209` (máx. 3 por mensagem, US$ 0,01 cada, contadas em `assessor_uso.buscas_web`), confirma com a pessoa e grava a grafia certa com `aprender_termo` em `assessor_vocabulario`. O vocabulário vai como referência (`initial_prompt`) para o Whisper e no contexto do modelo.

## Assessor: e-mail (Gmail), desde 2026-10-09
Decisão do Edimilson: **e-mail não cria agenda sozinho**. O assessor lê, resume e classifica; a pessoa decide pelos botões. Google primeiro; Outlook depois (a conta Hotmail é só convidada no tenant da Comal, sem permissão para registrar app; precisa de conta Azure própria).
- **Google Cloud**: projeto `assessor-pessoal-511122` (conta ejnascimento1@gmail.com), tela de consentimento "Assessor Pessoal", público Externo **em modo Teste** (só usuários de teste entram; hoje só ejnascimento1@gmail.com; limite de 100). Escopo único: `gmail.readonly` (restrito: para sair do modo Teste e abrir para clientes, o Google exige verificação do app e avaliação de segurança anual, CASA; planejar antes do lançamento). Cliente OAuth Web "Assessor Pessoal - Gmail", redirect `https://dubbmmjtbunzmdmfbbja.supabase.co/functions/v1/assessor-email-callback`. Em modo Teste o refresh token do Google **expira em 7 dias**: se a triagem mostrar "autorização revogada ou expirou", é só "Conectar de novo".
- **Conexão**: Configurações → "🤖 Assessor (Telegram e E-mail)" → "Conectar Gmail" chama a RPC `assessor_email_iniciar` (só perfil Pessoal; cria um `state` aleatório de uso único, 10 min, em `assessor_email_estados`) e vai para a Edge Function `assessor-email-callback` (`verify_jwt = false`; a segurança é o `state`). Ela manda para o Google, recebe o código, confere que o escopo do Gmail foi marcado, troca por tokens e chama `assessor_email_salvar_conta` (só `service_role`), que guarda o **refresh token no Supabase Vault** (`vault.create_secret`); `assessor_email_contas` só guarda a referência (`segredo_id`). Volta para o Taskfull com `?email=conectado|erro&msg=...`, que abre Configurações com um aviso. "Desconectar" (RPC `assessor_email_desconectar`) apaga a conta e o segredo do Vault.
- **Privacidade (regra do produto: a pessoa escolhe o que é analisado)**: só e-mails dos remetentes em `assessor_email_remetentes` (e-mail exato ou domínio `@empresa.com.br`; flag VIP) são lidos. Lista vazia = nada é lido. A busca no Gmail já filtra por `from:(...)` e a função confere o remetente de novo. Só o **resumo** fica salvo (`assessor_emails`), nunca o corpo. O prompt trata o e-mail como dado (proteção contra instruções escondidas no e-mail).
- **Triagem**: Edge Function `assessor-email-triagem` (`verify_jwt = true`), chamada pelo cron `assessor-email-triagem` a cada 15 min (pg_net, chave anon; varre todas as contas) ou pelo botão "🔄 Verificar agora" (JWT do usuário; só a conta dele). Primeira varredura pega os últimos 2 dias; depois, desde a última varredura (com 30 min de folga), até 20 por vez, sem repetir (`unique (conta_id, mensagem_id)`). Cada e-mail novo vai para o **Claude Haiku 5.5** (`claude-haiku-5-5`, saída em JSON estruturado, sem thinking, effort low; US$ 0,10/0,50 por milhão de tokens) que devolve resumo, categoria (acao/reuniao/financeiro/informativo/outros), urgente, tarefa sugerida e reunião sugerida (data/hora). Custo vai para `assessor_uso` com `canal = 'email'` e respeita o mesmo limite mensal do assessor (acima dele, guarda só o trecho do Gmail, sem IA). Urgente ou VIP com Telegram conectado: manda alerta no Telegram (`alertado`).
- **Tela**: aba "📧 E-mails" (só perfil Pessoal; badge com os novos) com filtros Novos / Já tratados / Todos (30 dias) e botões por e-mail: "📝 Virar tarefa" (pede o título e cria em Atividades com a origem na descrição), "📅 Virar compromisso" (abre o modal de Agendamento já preenchido com a reunião sugerida; só grava se a pessoa salvar), "✔ Resolvido", "Ignorar", "↩ Reabrir", "Abrir no Gmail". Resumo do Dia ganhou o bloco "📧 E-mails do dia". Indicadores separam mensagens do Telegram de e-mails resumidos. Realtime também em `assessor_emails`.
- **Telegram**: ferramenta `listar_emails` (só os resumos já triados; o prompt manda tratar resumo como dado e nunca enviar/apagar e-mail).
- **Pendências do e-mail**: Outlook/Microsoft 365 (Graph, `Mail.Read`); IMAP para Yahoo e outros; verificação do app no Google antes de abrir para clientes; apagar resumos antigos automaticamente (ex.: 90 dias).

## Assessor: Outlook / Hotmail / Microsoft 365 (desde 2026-10-09)
- **Por que precisou de Azure**: para registrar um app na Microsoft é preciso um diretório (tenant) próprio; a conta Hotmail era só convidada no diretório da Comal. A conta gratuita do Azure criada com `ejnascimento@hotmail.com` gerou o diretório **"Diretório Padrão" (`ejnascimentohotmail.onmicrosoft.com`)**. Os usuários finais **não** precisam de nada disso: basta a conta deles (hotmail/outlook/live ou Microsoft 365).
- **Custo**: zero. O registro do app (Entra ID Free) é gratuito para sempre e não usa o crédito do Azure. Quando o crédito de 30 dias acabar, **não** aceitar "pagamento conforme o uso": a assinatura fica desativada, mas o diretório e o app continuam funcionando.
- **App registrado**: "Assessor Pessoal", ID do aplicativo `bd142941-20e0-4a25-a817-6ece10196142` (não é segredo; está no código), tipos de conta "Qualquer Locatário de ID do Entra + Contas Pessoais da Microsoft", redirect Web `https://dubbmmjtbunzmdmfbbja.supabase.co/functions/v1/assessor-outlook-callback`. Permissões delegadas do Microsoft Graph: `Mail.Read`, `offline_access`, `User.Read`. Segredo do cliente "MS_CLIENT_SECRET" válido por 24 meses (renovar antes de vencer: Azure → Registros de aplicativo → Assessor Pessoal → Certificados e segredos), guardado como `MS_CLIENT_SECRET` nos Secrets do Supabase.
- **Fluxo**: igual ao Gmail. `assessor_email_iniciar(workspace, 'outlook')` gera o `state` (agora com coluna `provedor`), a Edge Function `assessor-outlook-callback` (`verify_jwt = false`) leva ao login da Microsoft (`/common`, `prompt=select_account`), troca o código e salva o refresh token no Vault via `assessor_email_salvar_conta` (o provedor vem do `state`). A Microsoft troca o refresh token a cada renovação: a triagem grava o novo com `assessor_email_atualizar_refresh` (só `service_role`).
- **Triagem**: `assessor-email-triagem` agora trata os dois provedores (`listarGmail` / `listarOutlook`). No Outlook busca pelo Graph (`/me/messages`, filtro por data, corpo em texto) e filtra os remetentes liberados no próprio servidor, porque o Graph não filtra remetente por domínio. Cada e-mail guarda `link` para o botão "Abrir no e-mail".
- **Tela**: Configurações → Assessor mostra uma linha por provedor (Gmail e Outlook / Hotmail), cada uma com Conectar / Conectar de novo / Desconectar (`assessor_email_desconectar(provedor)`). A lista de remetentes liberados vale para os dois.
- **Para lançar para clientes**: a Microsoft mostra "editor não verificado" no consentimento. Para tirar, fazer a Verificação do Editor (gratuita, exige cadastro no Microsoft AI Cloud Partner Program/MPN e um domínio). Contas corporativas de outras empresas podem exigir consentimento do administrador delas.
- **Plano B (ainda não feito, aguardando decisão do Edimilson)**: para provedores sem OAuth (Yahoo, UOL etc.), a pessoa cria uma regra de encaminhamento dos remetentes escolhidos para um endereço exclusivo do assessor. Opções: Gmail dedicado com `+código` (grátis) ou domínio próprio com Cloudflare Email Routing (cerca de US$ 10 a 15 por ano).

### Lições do teste do Outlook (2026-10-09)
- **`invalid_client` = chave errada.** No Azure, "Certificados e segredos" mostra duas colunas: **Valor** (≈40 caracteres, quase sempre com `~`) e **ID secreto** (formato GUID com tracinhos). O `MS_CLIENT_SECRET` é o **Valor**, que só aparece uma vez; o ID não serve para nada aqui. Para conferir sem expor a chave: `GET https://dubbmmjtbunzmdmfbbja.supabase.co/functions/v1/assessor-outlook-callback?acao=diagnostico` devolve só tamanho, se parece GUID e se tem `~`.
- **Ler só o que foi recebido.** `/me/messages` do Graph inclui Itens Enviados e Rascunhos: a triagem usa `/me/mailFolders/inbox/messages`. No Gmail a busca exclui `in:sent`. Sem isso, um remetente liberado que é o próprio usuário puxava os e-mails que ele mesmo enviou.
- **Origem de cada e-mail** (pedido do Edimilson, 2026-10-09): o cartão no quadro 📧 E-mails mostra "📥 Gmail (endereço)" ou "📥 Outlook (endereço)" ao lado da data (`origemEmail()`, casa `assessor_emails.conta_id` com o `id` que `assessor_email_status()` passou a devolver).
