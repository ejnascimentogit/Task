# Documentação Técnica — Taskfull

> Este documento descreve o app real deste repositório (`index.html` + `workspace-schema.sql`, publicado no Cloudflare Pages como **"taskfull"** — ver `deploy/wrangler.jsonc`). Não confundir com `documentacao-gestao-implantacao.md`, que documenta o sistema de referência original (`painel-implantacao.html`/`supabase-schema.sql`, o Painel de Implantação da Intelipulse, single-tenant) do qual o Taskfull nasceu. O Taskfull pega a mesma arquitetura (arquivo único, sem build, Supabase direto do navegador, render manual) e adiciona uma camada de **multi-tenant real via workspaces**.

## 1. O que é

Um painel operacional (tarefas, agenda, pendências, "clientes"/entidades com status de saúde, treinamentos) que qualquer pessoa pode usar pra si mesma ou para uma equipe — cada usuário cria um ou mais **workspaces**, escolhe um **perfil** na criação, e convida outras pessoas por código ou e-mail quando o perfil permitir equipe.

- **Arquivo único**: `index.html` (2853 linhas), sem framework, sem build step — mesmo padrão do sistema de referência.
- **Backend**: Supabase (projeto próprio, diferente do projeto `implantation` do Painel de Implantação) — URL e chave publishable/anon ficam hardcoded no topo do `<script>` (linha ~1021), igual ao padrão já usado nos outros projetos: seguro expor a anon key, nunca a `service_role`.
- **Deploy**: Cloudflare Pages, projeto chamado **`taskfull`** (`deploy/wrangler.jsonc`, `assets.directory: "./public"`). `deploy/public/index.html` é uma cópia idêntica do `index.html` da raiz — **sempre que editar o `index.html` da raiz, copiar por cima de `deploy/public/index.html`** antes de publicar (mesmo fluxo de sincronização já usado no Painel de Implantação entre a raiz e `implantation-app/`).

## 2. Diferença central em relação ao sistema de referência: multi-tenant real

O Painel de Implantação (referência) é **single-tenant**: uma instância, um banco, uma equipe, RLS permissiva (`using (true)`) coberta só pela tela de login. O Taskfull precisa hospedar **múltiplos usuários/equipes desconhecidas entre si no mesmo banco**, então:

- Toda tabela de domínio ganhou uma coluna `workspace_id`, e a **RLS é real** (`workspace-schema.sql`, seção 5) — baseada em funções `is_member(ws_id)`/`is_admin(ws_id)` que checam `workspace_membros`, não em `using (true)`.
- Não existe mais uma tabela `pessoas` fixa da equipe — quem pertence a um workspace é uma linha em `workspace_membros`, criada por convite (e-mail) ou por código de convite.
- Storage (bucket `atividade-imagens`) segue o mesmo padrão de sempre, mas as policies de insert/delete agora exigem que o primeiro segmento do path seja um `workspace_id` do qual o usuário é membro (`storage.foldername(name)[1]::uuid`) — o app deve sempre gravar em `${workspaceId}/${atividadeId}/${arquivo}`.

## 3. Sistema de Workspaces e Perfis

Cada workspace tem um `perfil_tipo` fixo desde a criação (não muda depois), definido em `PERFIL_LABEL`/`PERFIL_DESC`/`PERFIL_ABAS` (index.html, linhas ~1032-1080):

| perfil (banco) | rótulo na tela | abas visíveis (`PERFIL_ABAS`) | rótulo padrão da entidade central (`ENTIDADE_LABEL_PADRAO`) |
|---|---|---|---|
| `pessoal` | **Pessoal** | Atividades, Agenda, Resumo | *(nenhuma — não tem aba de entidades)* |
| `equipe` | **Equipe** | Entidades, Agenda, Pendências, Atividades, Resumo | "Clientes" |
| `projeto` | **Gestão de Projeto** | Entidades, Agenda, Pendências, Atividades, Resumo, **Treinamentos** | "Projetos" |

Descrições mostradas nos cards de escolha do onboarding (`PERFIL_DESC`):
- Pessoal: "Só suas tarefas e sua agenda pessoal."
- Equipe: "Clientes, agenda, pendências, tarefas e resumo do dia pro time."
- Gestão de Projeto: "Tudo do modo Equipe, mais treinamentos/onboarding por etapas."

**Por que existem 3 e não um perfil único configurável**: o perfil decide, de uma vez, quais abas aparecem na sidebar (`abasAtivas()`/`temAba()`) e o nome da entidade central — em vez de cada workspace precisar configurar manualmente "quero aba de treinamentos, não quero aba de entidades", a pessoa escolhe um pacote pronto na hora de criar. `souSolo()` (`activeWorkspace.perfilTipo === 'pessoal'`) é o helper mais usado pra esconder tudo que depende de uma entidade central (já que o perfil Pessoal não tem `entidades`).

### 3.1 Fluxo de criação (onboarding)

`showOnboarding()` → `criarWorkspace()` (index.html ~1299-1328):
1. Usuário sem nenhum workspace ativo (`loadWorkspaces()` não encontra linha em `workspace_membros`) cai na tela de onboarding.
2. Escolhe um dos 3 cards de perfil (`selecionarPerfilOnboarding`, padrão pré-selecionado: `equipe`) e dá um nome ao workspace.
3. `criarWorkspace()` insere a linha em `workspaces` (`perfil_tipo`, `owner_id`, `entidade_label` já vindo de `ENTIDADE_LABEL_PADRAO[perfil]`).
4. O trigger `handle_new_workspace` (banco) cria automaticamente a linha do criador em `workspace_membros` como `admin`/`ativo` — sem isso ninguém conseguiria inserir a própria linha ali, já que a policy de insert exige já ser admin do workspace (problema de ovo-e-galinha resolvido no trigger, não no client).
5. `seedWorkspaceDefaults(wsId, perfil)` povoa as tabelas de configuração default **só das abas que aquele perfil tem** (`PERFIL_ABAS[perfil]`) — ex. perfil Pessoal não ganha `etapas` (exige aba `entidades`) nem `treinamentos_padrao` (exige aba `treinamentos`), mas ganha `tipos_agendamento` porque *tem* a aba Agenda. `kanban_colunas` é sempre semeada (`DEFAULT_KANBAN_COLUNAS`), já que Atividades é comum aos 3 perfis.

### 3.2 Múltiplos workspaces por usuário

Uma pessoa pode pertencer a vários workspaces (ex. um "Pessoal" próprio + um "Equipe" da empresa) — `loadWorkspaces()` carrega todos onde ela tem `workspace_membros.status = 'ativo'`, e `renderWsSwitcher()` desenha o seletor no topo (nome + tag do perfil) com um item "+ Criar novo workspace" que reabre o onboarding. O último workspace acessado fica salvo em `localStorage` (`ws_active_id`) e é restaurado no próximo login; se não existir mais (removido/sem acesso), cai no primeiro da lista.

## 4. Membros, papéis e convites

- **Papéis**: `admin` ou `membro` (`workspace_membros.role`). Quem cria o workspace vira admin automaticamente; só admin pode: renomear o workspace, trocar cores, mudar o modo de código de entidade, gerar novo código de convite, convidar por e-mail, remover membro, promover/rebaixar outro membro (`alternarRoleMembro`). Um admin não pode alterar o próprio papel nem se remover pela lista (`souEu` bloqueia essas ações no próprio card).
- **Dois caminhos de convite**, ambos guardados na mesma tabela `workspace_membros`:
  1. **Por e-mail** (`convidarPorEmail`): insere uma linha com `status='pendente'`, `user_id=null`. Quando essa pessoa se cadastra (trigger `activate_pending_invites`, `after insert on auth.users`) ou já tinha conta e loga depois (RPC `accept_pending_invites`, chamada em todo `afterAuth()`), a linha vira `status='ativo'` e ganha o `user_id`. Cobre os dois casos: convidar quem ainda não tem conta, e convidar quem já tem.
  2. **Por código de convite** (`invite_code`, 8 caracteres, gerado automaticamente na criação do workspace e regenerável por um admin em Configurações — `regenerarCodigoConvite`, invalida o código anterior). Quem recebe o código digita em "Você tem um código de convite?" no cadastro; se a conta ainda não existir, o código fica em `localStorage` (`ws_pending_invite_code`) até o signup completar, e só então `entrarComCodigoPendente()` chama a RPC `join_workspace_by_code`. A função é `security definer` de propósito — não dá pra validar "o usuário realmente tem o código certo" só com uma policy de insert direto na tabela, então a validação (existe workspace com esse código?) vive dentro da função.
- **Erro amigável de e-mail duplicado**: tentar convidar um e-mail já convidado/membro do mesmo workspace bate na constraint única `(workspace_id, lower(email))` — `mensagemErroAmigavel()` traduz o código Postgres `23505` pra "Esse e-mail já foi convidado ou já é membro deste workspace." em vez de mostrar o erro cru do Postgres.

## 5. Modelo de dados (o que muda em relação ao sistema de referência)

Tabelas e nomes de coluna equivalentes ao Painel de Implantação, mas renomeados de forma genérica (o domínio deixou de ser fixo em "clientes de implantação"):

| Taskfull | Equivalente na referência | Observação |
|---|---|---|
| `entidades` | `clientes` | campo `nome` genérico; rótulo exibido na tela vem de `workspace.entidade_label` (ex. "Clientes" no perfil Equipe, "Projetos" no perfil Gestão de Projeto) |
| `contatos_entidade` | `contatos_cliente` | mesma ideia (lista dinâmica de contatos) |
| `pendencias.responsavel` | idem | valores mudaram de `cliente`/`rscrm` pra **`entidade`/`equipe`** — genérico, não amarrado à Intelipulse |
| `agendamentos.entidade_id/entidade_nome` | `cliente_id/cliente_nome` | mesmo padrão soft-reference |
| `atividades.entidade_nome` | `atividades.cliente_nome` | idem, ainda texto livre obrigatório |
| `kanban_colunas` | `KANBAN_COLUMNS` (fixo no código, no sistema de referência) | **virou tabela editável por workspace** — cada workspace pode ter suas próprias raias além da fixa "Concluído" (`COLUNA_CONCLUIDA`, sempre reservada/fixa no app, nunca vive na tabela, por causa da regra de resolução obrigatória + histórico automático) |
| `agendamentos.atividade_id` | não existe na referência | liga um agendamento à atividade criada a partir dele (botão "Criar Atividade" no modal), evita duplicar o mesmo assunto ao converter reunião em tarefa |

Todas ganharam `workspace_id` (FK cascade) e entram nos `select` de `loadWorkspaceData()` sempre filtradas por `eq('workspace_id', wid)` — carregamento é 100% por workspace ativo, trocar de workspace refaz esse load inteiro (`selectWorkspace()`).

## 6. Regras de negócio específicas do Taskfull (sem equivalente na referência)

- **Código automático de entidade** (`workspaces.codigo_automatico`, boolean por workspace, configurável em Configurações → "Código de \<Entidade\>"): quando ligado, o campo código no formulário de nova entidade vem pré-preenchido e **somente leitura** com `proximoCodigoAutomatico()` (maior código numérico existente + 1); quando desligado, é digitação livre (sujeita à constraint única `(workspace_id, codigo)` — erro amigável via `mensagemErroAmigavel(..., 'codigo-entidade')`).
- **Identidade visual por workspace**: `cor_destaque` e `cor_fundo` são colunas do próprio workspace (não uma preferência de usuário) — qualquer membro que entra num workspace vê a paleta que o admin configurou ali (`aplicarCorDestaque`/`aplicarCorFundo`, aplicadas via CSS custom properties toda vez que `selectWorkspace()` roda). Diferente disso, tema claro/escuro e a intensidade de contorno de linhas **são preferência pessoal no navegador** (`localStorage`, chaves `ws_app_theme`/`ws_app_borda`), não amarradas a nenhum workspace — trocar de workspace não muda o tema, só a cor de destaque/fundo.
- **Sair vs. excluir workspace**: um membro pode sair de qualquer workspace que não seja o único do qual é admin (policy `"sair do workspace"`, delete direto por `user_id = auth.uid()`); excluir o workspace inteiro (cascade em tudo) é exclusivo de admin (`"delete admin workspace"`).
- **`souEu` trava ações destrutivas sobre a própria linha**: no card de cada membro em Configurações, a pessoa consegue editar o próprio nome (input inline) mas não o próprio papel nem se remover — evita um admin acidentalmente se rebaixar/remover e ficar sem acesso de admin ao próprio workspace (se for o único admin).
- **Nome de exibição dos membros (2026-09-21)**: em Configurações → Membros, cada pessoa edita o próprio nome e o **admin** também edita o nome dos outros (`salvarNomeMembro`, atualiza só `workspace_membros.nome`; a policy `update membros admin` já permite). Vale para qualquer perfil (o código não checa `perfil_tipo`), mas só faz diferença em Equipe e Gestão de Projeto, onde há mais de um membro. Quem é convidado por e-mail entra com o nome vazio (o convite grava `nome=''` e o trigger de ativação só preenche `user_id`/`status`), então aparece pelo e-mail nos filtros até alguém preencher. Renomear **não** altera `atividades.responsavel`/`agendamentos.responsavel` já gravados, que guardam o nome como texto.

## 7. Segurança

- A `SUPABASE_URL`/chave no topo do `index.html` é a **publishable/anon key** do projeto Supabase deste app (projeto próprio, diferente do `implantation`) — segura de expor num arquivo público, nunca a `service_role`.
- RLS é a defesa real aqui (diferente da referência, que documenta RLS permissiva como dívida técnica aceitável) — é obrigatória porque o mesmo banco hospeda dados de workspaces/usuários que não se conhecem entre si.
- Convite por código (`invite_code`) funciona como uma senha de baixa entropia (8 caracteres alfanuméricos) — suficiente pra "compartilhar um link com quem eu quero", não pra segredo de alta sensibilidade; quem se preocupar com vazamento do código tem a opção de regenerá-lo a qualquer momento (invalida o anterior).

## 8. Publicação (deploy)

- O projeto Cloudflare `taskfull` está conectado ao GitHub desde 2026-09-21 (Workers Builds): repositório `ejnascimentogit/Task`, branch `master`, diretório raiz `deploy`, comando `npx wrangler deploy`, com token de build próprio. **Todo push no `master` publica sozinho.** Antes disso os deploys eram manuais (`wrangler deploy`).
- Site: `https://taskfull.ejnascimento1.workers.dev`. Esta documentação em formato de página fica em `/docs` (o `/docs.html` redireciona para `/docs`).
- Só `deploy/public/` é publicado: editar o `index.html` da raiz exige copiar por cima de `deploy/public/index.html`.
- **E-mail de confirmação**: o Supabase sem SMTP próprio só entrega e-mail para membros da organização do projeto, então quem se cadastra de fora pode não receber a confirmação. A correção definitiva é configurar SMTP próprio (Brevo ou Resend) em Authentication → SMTP Settings; até lá, confirmar a conta em Authentication → Users → "Confirm user". O convite por e-mail do workspace **não envia e-mail nenhum**: só pré-autoriza o endereço, e o convidado precisa ser avisado por fora.

---

*Gerado a partir da leitura de `index.html` e `workspace-schema.sql` deste repositório. Se o código mudar, atualizar este documento junto — ele descreve decisões e comportamento, não só estrutura, então fica desatualizado silenciosamente se só o código for editado.*
