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
