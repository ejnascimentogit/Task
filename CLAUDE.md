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
- Medidor: `assessor_uso` grava tokens (entrada, saída, cache lido/gravado) e custo estimado por mensagem. Indicadores → "🤖 Uso do Assessor Pessoal" mostra mensagens do mês, gasto do mês, quanto ainda pode gastar (`assessor_vinculos.limite_mensal_usd`, padrão US$ 3) e total, em US$ e R$ (AwesomeAPI, reserva 5,5).
- Tabelas: `assessor_vinculos`, `assessor_mensagens`, `assessor_uso`, `assessor_lembretes_enviados` (schema em `workspace-schema.sql`). Código das funções em `supabase-edge-functions/assessor-telegram` e `supabase-edge-functions/assessor-lembretes` (deploy feito pelo MCP do Supabase; ao mudar, publicar de novo).

**Segredos (Supabase → Edge Functions → Secrets, nunca em arquivo)**: `TELEGRAM_BOT_TOKEN` (do @BotFather; se vazar, `/revoke` e trocar), `ANTHROPIC_API_KEY` (conta individual da Anthropic, workspace "Assessor Pessoal", chave "Assessor Pessoal - teste" até 31/12/2026, limite US$ 3/mês), `OPENAI_API_KEY` (pendente, para transcrever áudio).

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
