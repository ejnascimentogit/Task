# Documentação Completa — Sistema de Gestão de Implantação

> **Como usar este documento**: isto é a especificação completa de um sistema já construído e testado em produção (o "Painel de Implantação" da Intelipulse), pensada pra você (ou uma IA) reconstruir/adaptar o mesmo sistema em outro projeto, com outra finalidade. Junto com este arquivo, anexe também:
> - `painel-implantacao.html` — o código-fonte completo (front-end + back-end, já que é tudo client-side conversando direto com o Supabase)
> - `supabase-schema.sql` — o schema SQL completo do banco
>
> Este documento explica **o quê** cada peça faz, **por quê** ela existe daquele jeito específico (decisões não óbvias só olhando o código), e **como** adaptar pra outro contexto. Os dois arquivos anexos são a implementação de referência; esta documentação é o "manual de arquitetura" pra entender e portar.

---

## 1. Visão geral

É uma ferramenta de gestão operacional diária para uma equipe pequena (poucas pessoas), cobrindo: cadastro de "contas"/clientes com status de saúde, agenda de reuniões/ligações, quadro Kanban de tarefas do dia a dia, pendências por conta, treinamentos/onboarding por etapas, e um resumo diário exportável pra compartilhar com terceiros (diretoria, grupo de WhatsApp, etc.).

Características centrais do sistema, independente do domínio de negócio:

- **Um único arquivo HTML** (`painel-implantacao.html`) — sem build step, sem framework (React/Vue/etc.), JavaScript puro (vanilla) manipulando o DOM diretamente via `innerHTML` e `document.getElementById`. Abre com duplo clique ou é hospedado como site estático.
- **Backend = Supabase** (Postgres + REST autogerado + Auth + Storage), acessado direto do navegador via `supabase-js` (CDN). Não existe servidor próprio, não existe API intermediária.
- **Sem build/bundler**: tudo é `<style>` e `<script>` inline no mesmo arquivo. Isso é uma escolha deliberada pra manter a barreira de entrada baixíssima (qualquer pessoa da equipe consegue abrir e editar o arquivo sem precisar de Node, npm, etc.), ao custo de o arquivo ficar grande (~3800 linhas na versão de referência).
- **Renderização manual**: não há reatividade automática (nada tipo Vue/React). Cada tela tem uma função `renderX()` que reconstrói o HTML daquela seção a partir do estado em memória (`state`, arrays globais). Depois de qualquer mudança (salvar, excluir, marcar como feito), é preciso **chamar explicitamente** a função de render certa — esquecer isso é a causa mais comum de bug nesse tipo de arquitetura (dado salva no banco mas a tela não atualiza até trocar de aba).

Ao portar pra outra finalidade, a arquitetura (arquivo único, Supabase direto, render manual) pode ser mantida como está — ela funciona bem pra esse porte de equipe/produto. O que muda é o domínio: troque "clientes com etapa de onboarding" pelo conceito equivalente do novo contexto (pode ser "processos", "projetos", "candidatos", "pedidos" — qualquer entidade central que passa por um funil e tem status de saúde/risco).

---

## 2. Arquitetura técnica

### 2.1 Estrutura do arquivo `painel-implantacao.html`

```
<head>
  <style> ... </style>          -- todo o CSS do sistema, com variáveis em :root
</head>
<body>
  <div id="auth-screen"> ... </div>   -- tela de login/cadastro (cobre a tela até logar)
  <div id="app">
    <aside class="sidebar"> ... </aside>   -- menu lateral de navegação
    <main>
      <section id="view-X"> ... </section>  -- uma seção por aba, todas no DOM,
      <section id="view-Y"> ... </section>  -- visibilidade controlada por style.display
      ...
    </main>
  </div>
  <!-- modais (overlay + box), um por entidade editável -->
  <script src=".../supabase-js@2/..."></script>
  <script>
    const sb = supabase.createClient(URL, ANON_KEY);
    let state = { ... };            -- estado em memória, uma cópia local do banco
    async function loadState() { ... }  -- busca tudo do Supabase no boot e após login
    function render() { ... }           -- dispatcher: chama a render function da aba ativa
    function renderX() { ... }          -- uma por aba/entidade, reconstrói o HTML via innerHTML
    async function saveX() { ... }      -- grava no Supabase E atualiza o array em memória
    ...
  </script>
</body>
```

### 2.2 Padrão de dados: estado em memória espelhando o banco

No boot (`loadState()`), o app faz um `select('*')` de cada tabela relevante e guarda em variáveis JS globais (arrays de objetos, com nomes de campo em camelCase — o banco usa snake_case, então o mapeamento `data: c.cliente_id → clienteId: c.cliente_id` acontece nessa função). Depois disso, toda leitura da tela usa esse estado em memória, não o banco direto — só as operações de escrita (`saveX`/`deleteX`/`toggleX`) tocam o Supabase, e em seguida atualizam o array local (`Object.assign` no objeto existente, ou `.push()`/`.filter()`).

**Regra crítica de manutenção**: uma função que salva algo "em silêncio" (sem fechar modal, ex. salvar um sub-item dentro de um modal aberto) só atualiza o array em memória — não redesenha a tela inteira, pra não fechar o modal debaixo do usuário. Isso significa que qualquer dado exibido **fora** daquele modal (contadores no topo, badges em outra aba) precisa de uma chamada explícita à função de render daquele pedaço específico. Esse é o bug mais recorrente desse tipo de arquitetura — vale ter um checklist mental: "esse save muda algo que aparece em outro lugar da tela? Se sim, chamar a render function daquele lugar."

### 2.3 Padrão "soft reference" (referência textual + link opcional)

Vários relacionamentos no sistema não são FKs rígidas — são um par de campos: um texto livre sempre salvo (ex. `cliente_nome`), e um ID opcional que só é preenchido quando o texto bate com um registro já cadastrado (ex. `cliente_id`, resolvido via `state.clients.find(c => c.nome.toLowerCase() === nomeDigitado.toLowerCase())`). Isso permite:

- Referenciar uma entidade que ainda não existe formalmente no sistema (ex. agendar reunião com um "lead"/prospect antes de ele virar cliente cadastrado).
- Excluir a entidade "pai" (ex. uma pessoa da equipe) sem quebrar os registros antigos que a referenciavam — eles continuam mostrando o nome como texto, só somem dos filtros/dropdowns.

Esse padrão se repete em: `agendamentos.cliente_nome`/`cliente_id`, `atividades.cliente_nome` (sem ID, só texto — não existe conceito de "lead" ali), `atividades.responsavel`/`criado_por` (texto solto, não FK pra tabela de pessoas).

### 2.4 Tabelas de configuração editáveis (em vez de enums fixos no código)

Toda "lista de opções" que a equipe pode querer mudar ao longo do tempo (etapas do funil, tipos de evento de agenda, pessoas da equipe) é uma **tabela própria no banco**, gerenciável por uma tela de Configurações dentro do próprio app — não um `enum`/`CHECK constraint` fixo no schema, nem um array hardcoded no JS. O motivo: alterar uma lista fixa exigiria mexer no banco (constraint) e no código (select options, mapas de label/ícone) toda vez que alguém precisasse adicionar uma opção — na prática isso gerava atrito e pedidos repetidos. O padrão adotado:

- Tabela com `id` (slug texto), `nome`, `ordem` (int, pra permitir reordenar), e campos extra conforme o caso (`cor` pra etapas, `icone` pra tipos de agenda).
- O JS carrega a tabela pra um array global no boot e reconstrói os mapas auxiliares (ex. `TIPO_ICON`/`TIPO_LABEL`) a partir dela.
- A tela de Configurações permite adicionar/renomear/reordenar/excluir, com uma trava: **não deixa excluir uma opção que já está em uso** por algum registro (a mensagem pede pra trocar os registros existentes primeiro) — evita registros órfãos com um tipo/etapa inexistente.
- Não há FK do lado das tabelas de dados pra essas tabelas de configuração (mesmo padrão "soft reference" acima) — um registro antigo referenciando um `tipo` já excluído simplesmente não acha ícone/label (fallback genérico), mas não quebra.

### 2.5 Autenticação

Login/cadastro via Supabase Auth (e-mail+senha), numa tela que cobre o app inteiro até logar. Pontos de atenção pra replicar:

- **Restrição de domínio de e-mail no cadastro** (se aplicável ao novo contexto — ex. só e-mails corporativos): trava tanto no front (validação antes de chamar `signUp`) quanto num **trigger no banco** (`before insert on auth.users`), porque a trava de front sozinha é contornável chamando a API direto.
- **Vínculo automático conta↔pessoa**: um trigger `after insert on auth.users` procura na tabela de "pessoas da equipe" um registro com o mesmo nome (vindo de `raw_user_meta_data`) e linka via `user_id`; se não achar, cria um registro novo. Isso evita ter que gerenciar usuários em dois lugares separados.
- **RLS pode ficar permissivo (`using (true)`) numa primeira fase**, com a tela de login servindo só de barreira de front-end — é aceitável pra uma ferramenta interna pequena, mas documente isso claramente como dívida técnica se for o caso, porque não é proteção de dados real. Uma segunda fase (travar RLS de verdade com `auth.uid()`) fica como próximo passo natural.
- **Pegadinhas reais de configuração do Supabase** (não são bugs de código, mas comem tempo de diagnóstico se não souber):
  - O "Site URL" do projeto Supabase por padrão aponta pra `localhost:3000` — o link de confirmação de e-mail redireciona pra lá (erro de "site inacessível") mesmo a confirmação já tendo funcionado no servidor. Corrija em **Authentication → URL Configuration** assim que tiver a URL final de produção.
  - O serviço de e-mail padrão do Supabase (sem SMTP próprio) tem limite de poucos e-mails por hora por projeto, não ajustável direto no dashboard. Com vários cadastros no mesmo dia, esbarra em `over_email_send_rate_limit`. Solução sem SMTP customizado: esperar o limite resetar, ou o admin criar a conta manualmente em **Authentication → Users → Add user** com "Auto Confirm User" marcado.

---

## 3. Modelo de dados completo

> Nomes de tabela/campo abaixo são os do sistema de referência (domínio "implantação de clientes"). Ao portar pra outra finalidade, troque os nomes de domínio (ex. `clientes`→`processos`, `etapa`→`fase_do_funil`) mas **mantenha a estrutura relacional e as regras** — elas resolvem problemas reais, não são específicas do domínio original.

### `clientes` (entidade central)
| coluna | tipo | significado |
|---|---|---|
| `id` | uuid pk | |
| `codigo` | text unique | identificador curto que a equipe já usa informalmente (numeração interna) |
| `nome` | text not null | |
| `responsavel` | text | responsável pelo lado do cliente (não da equipe interna) |
| `etapa` | text | fase do funil/onboarding — referência solta à tabela `etapas` |
| `fase` | text: `implantacao` \| `base` | eixo **independente** de `etapa`: indica se a entidade está no ritmo ativo diário ou "dormente"/só manutenção pontual |
| `saude` | text: `verde`\|`amarelo`\|`vermelho` | status de risco (padrão RAG/Gainsight), **independente** de `etapa` — pode estar travado (vermelho) em qualquer fase do funil |
| `saude_motivo` | text | só relevante quando `saude` ≠ verde |
| `observacao` | text | texto livre pra particularidades que não cabem em nenhum campo estruturado (preferência de horário, restrição de canal, etc.) |
| `inicio` | date | |
| `ultimo_contato` / `proximo_contato` | date | alimentam indicadores de "contatos pendentes"; `proximo_contato = null` = dormente, não conta nos indicadores |
| `created_at`/`updated_at` | timestamptz | |

**Importante**: `etapa`, `fase` e `saude` são três eixos ortogonais. É comum, ao adicionar uma feature nova, checar o eixo errado por engano (ex. um filtro que devia olhar `fase` acaba olhando `etapa`). Se algo não aparece onde devia, esse é o primeiro lugar a checar.

### `contatos_cliente` (lista dinâmica, 1-N)
`id, cliente_id (fk cascade), nome, telefone, cargo (texto livre, ex: "Financeiro"), created_at`. Existe porque um número fixo de campos de contato (contato1/telefone1/contato2/telefone2...) não escala — a equipe pode precisar de quantos contatos quiser por entidade.

### `pendencias`
`id, cliente_id (fk cascade), texto, responsavel (check: 'cliente'|'rscrm' — ou seja, "travou do lado de quem"), feito boolean, created_at`. Editável em dois lugares da UI simultaneamente (modal de detalhe da entidade, e uma aba dedicada que mostra todos os cards de uma vez) — **por isso o código usa duas famílias de funções paralelas** (uma que assume "a entidade sendo editada agora" via uma variável global `editingXId`, outra que recebe o ID explicitamente porque a tela mostra várias entidades ao mesmo tempo). Qualquer mudança de comportamento em pendências precisa ser replicada nas duas famílias, senão divergem silenciosamente.

### `historico`
`id, cliente_id (fk cascade), data date, texto, created_at`. Log cronológico (mais recente primeiro) de contatos e eventos (mudança de saúde, mudança de fase, resumo de tarefas concluídas relacionadas àquela entidade). É o "diário" de cada entidade.

### `etapas` (configuração editável — ver §2.4)
`id (text pk, slug), nome, cor, ordem, created_at`.

### `pessoas` (equipe — configuração editável)
`id uuid pk, nome unique, ordem, user_id (fk auth.users, nullable, unique), apenas_visualizacao boolean, created_at`. `apenas_visualizacao` — pessoa que só acompanha (ex. um sócio/gestor), não some do sistema mas some dos filtros e dropdowns de "responsável".

### `tipos_agendamento` (configuração editável — ver §2.4)
`id (text pk, slug), nome, icone, ordem, created_at`.

### `agendamentos` (agenda com data **e hora**, diferente de `proximo_contato` que é só data)
| coluna | significado |
|---|---|
| `cliente_id` / `cliente_nome` | soft reference (ver §2.3) — permite agendar com algo ainda não cadastrado formalmente |
| `titulo`, `tipo`, `data`, `hora`, `observacao` | |
| `feito` | boolean |
| `responsavel` | quem agendou/vai conduzir (texto solto) |
| `participantes` | `text[]` — pra eventos com mais de uma pessoa da equipe |
| `reagendado_de` | `date`, nullable — quando a **data** de um agendamento existente muda num save, o sistema grava ali a data anterior automaticamente (sem ação manual). A UI mostra um selo "🔁 Reagendado" com a data antiga em tooltip. Se remarcado de novo depois, sobrescreve com a data imediatamente anterior (só guarda a última, não um histórico completo). |

A tela de Agenda tem 3 visualizações (Lista agrupada por mês, Cards, Calendário em grade estilo Outlook só com dias que têm evento), busca por texto, filtro por pessoa, e lembrete visual (toast) + notificação nativa do navegador quando um evento de hoje está próximo (checado a cada 30s, dispara entre 15 min antes e 5 min depois do horário).

### `atividades` (quadro Kanban — "o que cada pessoa está fazendo hoje", não é por entidade/cliente)
| coluna | significado |
|---|---|
| `responsavel` | quem vai executar |
| `criado_por` | quem **pediu** a tarefa (diferente de responsável — existe pra registrar formalmente quando uma pessoa pede algo pra outra executar, sem precisar de gambiarra tipo escrever "(Fulano) fazer X" no campo de descrição) |
| `titulo` | descrição (multi-linha) |
| `cliente_nome` | soft reference textual (obrigatório no formulário — ver regra abaixo) |
| `label` | cor de etiqueta (`red`\|`orange`\|`yellow`\|`blue`, nullable) |
| `coluna` | `urgencias`\|`afazer`\|`andamento`\|`concluida` — colunas fixas do Kanban (não é uma tabela configurável, porque o fluxo de trabalho em si — "fila, a fazer, em andamento, concluído" — é estrutural, diferente de "tipos de evento" que são só rótulos) |
| `urgente` / `cancelado` | boolean |
| `resolucao` | o que foi feito — **obrigatório** antes de mover pra "concluída" (ver regra abaixo) |
| `participantes` | `text[]` |
| `concluido_em` | date |
| `ordem` | int, pra ordenação manual dentro da coluna |

**Regras de negócio importantes** (não óbvias olhando só o schema):
- **Entidade (cliente_nome) é obrigatória pra salvar** — é o que permite, ao concluir a tarefa, registrar automaticamente uma entrada no `historico` daquela entidade (por casamento de nome, case-insensitive). Se esse campo virar opcional de novo, esse elo quebra silenciosamente.
- **Resolução é obrigatória antes de mover pra "concluída"** — tanto pelo modal quanto arrastando no board (o drop na coluna "concluída" não salva nada sozinho, só abre o modal já com a coluna selecionada e o foco no campo de resolução; se a pessoa fechar sem preencher, nada muda).
- **O gatilho de "registrar no histórico" não é só "coluna virou concluída uma vez"** — é "coluna é concluída **E** algo relevante mudou desde o último save" (entidade mudou, ou resolução mudou). Isso cobre o fluxo real de uso: arrastar rápido pro concluído sem preencher nada, e só depois voltar no card pra completar os detalhes — se o gatilho fosse só na primeira transição de coluna, essa edição posterior nunca geraria o registro de histórico.

### `atividade_imagens` (N imagens por atividade)
`id, atividade_id (fk cascade), path, url, created_at`. Arquivos ficam no **Supabase Storage** (bucket público dedicado, com policies próprias de select/insert/delete); a tabela só guarda a referência. Upload por botão OU colar (Ctrl+V) direto no modal — os dois caminhos chamam a mesma função de upload compartilhada, pra qualquer mudança de lógica (nome do bucket, tratamento de erro) só precisar ser feita uma vez.

### `treinamentos_etapas` / `treinamentos_padrao` / `treinamento_etapa_atividades` (opcional — só se o domínio novo tiver um conceito de "onboarding com etapas supervisionadas")
Estrutura pra acompanhar um checklist de etapas de treinamento por entidade, cada etapa com analista responsável, data/hora, link de reunião, e lembrete (mesmo mecanismo de toast/notificação da Agenda, disparando 1h antes).

---

## 4. Telas / abas e suas regras de negócio

Cada aba é uma `<section>` sempre presente no DOM, com `style.display` alternado por uma função `setTab(nome)` que também dispara `render()`.

- **Lista/Cards de entidades** (ex. "Clientes"): tabela ou grade de cards, com busca e filtro por fase; badges de saúde (RAG) e fase.
- **Detalhe/edição** (modal): formulário com todos os campos estruturados + seções aninhadas editáveis inline (contatos, pendências, histórico) sem precisar de telas separadas.
- **Pendências (visão geral)**: um card por entidade com pendências abertas, ordenado por critério configurável (no sistema de referência: código da entidade crescente — já foi "quantidade de pendências abertas" numa versão anterior, trocado a pedido de quem usa, pra facilitar achar uma entidade específica). Marcar/desmarcar um item nessa tela **não** re-renderiza os cards inteiros — só atualiza a lista daquele card específico, pra evitar que os cards "pulem de lugar" enquanto alguém está mexendo neles.
- **Agenda**: ver §3, tabela `agendamentos`.
- **Atividades (Kanban)**: ver §3, tabela `atividades`. Tem filtro por pessoa (compartilhado com a Agenda — mesma variável global), e um botão de "Gerar Relatório" que monta um resumo do dia agrupado por entidade → pessoa, exportável como texto ou como imagem (via html2canvas).
- **Resumo do Dia**: mostra só o que foi **concluído hoje**, agrupado em dois níveis (entidade → pessoa), pensado pra colar num canal de comunicação externo (grupo, e-mail). Texto puro, sem HTML, preservando quebras de linha.
- **Configurações**: acordeão (cada bloco começa fechado, abre ao clicar no título) com uma seção por tabela de configuração editável (ver §2.4) — etapas, pessoas, tipos de evento, backup (export/import de todo o `state` como JSON).

---

## 5. Convenções de estilo (CSS)

Todo o CSS usa **variáveis em `:root`** (cor primária escura, cor de destaque, texto, fundo, bordas), com um bloco `:root[data-theme="dark"]` + `@media (prefers-color-scheme: dark)` redefinindo as mesmas variáveis pra dark mode automático. Duas variáveis merecem atenção especial ao portar:

- Uma cor que **muda de significado** entre os temas (ex. "branco" vira "card escuro" no dark mode) precisa de uma variável **separada e fixa** pra qualquer elemento que precisa ficar sempre com aquela cor independente do tema (ex. texto sobre um fundo escuro fixo, tipo a barra lateral). Reaproveitar a variável errada nesse caso deixa o texto ilegível só no dark mode — bug fácil de não notar em desenvolvimento se você sempre testa no tema claro.
- `overflow-x: hidden` no `html`/`body` (pra evitar rolagem horizontal indesejada) tem um efeito colateral: qualquer `overflow` diferente de `visible` no eixo X força o navegador a tratar o eixo Y como `auto` também, o que quebra `position: sticky` em qualquer elemento que dependa disso (ex. uma barra lateral fixa). Use `overflow-x: clip` em vez de `hidden` pra evitar esse efeito colateral mantendo o mesmo resultado visual.

---

## 6. Publicação / deploy

O sistema de referência usa hospedagem estática (GitHub Pages) com deploy automático a cada `git push`, a partir de um repositório separado que serve só o `index.html` publicado (cópia do arquivo-fonte). Qualquer hospedagem de arquivo estático serve (Netlify, Vercel, S3+CDN, etc.) — a única exigência é servir um único arquivo HTML sobre HTTPS. Não há build step nenhum: publicar = copiar o arquivo pro lugar certo.

Pontos de atenção genéricos (independente da hospedagem escolhida):
- Configure a "Site URL" / URL de redirecionamento de confirmação de e-mail no Supabase Auth pra apontar pra URL final de produção assim que ela existir (ver §2.5).
- Se usar mais de um ambiente de hospedagem apontando pro **mesmo banco** (ex. um antigo esquecido e um novo), tenha cuidado: as duas URLs vão ler/gravar dados reais igualmente, mas só a mais atualizada tem as features de código mais recentes — um comportamento "funciona pra uma pessoa mas não pra outra" costuma ser exatamente isso (URL diferente, não bug de lógica).

---

## 7. Checklist pra reconstruir em outro contexto

1. Definir a entidade central (equivalente a "clientes") e seus três eixos independentes de status, se fizer sentido pro domínio (posição no funil / ativo-ou-dormente / saúde-risco).
2. Criar o schema SQL (adaptar `supabase-schema.sql`) com RLS permissivo pra começar, tabelas de configuração editáveis em vez de enums fixos onde a lista pode crescer, e o padrão soft-reference em qualquer relação que precise sobreviver à exclusão do lado referenciado ou apontar pra algo ainda não cadastrado.
3. Montar o arquivo único (adaptar `painel-implantacao.html`): copiar a estrutura de `:root` CSS, sidebar, seções por aba, padrão de modal, e a lógica de `loadState()`/`render()`/`saveX()` por entidade.
4. Portar a Agenda como módulo (já documentado separadamente, ver arquivo `agenda-modulo-reutilizavel.html` gerado anteriormente) se o novo domínio também precisar de reuniões/compromissos com hora.
5. Portar o Kanban de atividades se o novo domínio também precisar de "o que cada pessoa está fazendo hoje" separado do funil da entidade central.
6. Implementar autenticação (Fase 1: login/cadastro + vínculo automático a um cadastro de pessoas; Fase 2, quando fizer sentido: travar RLS de verdade).
7. Escolher hospedagem estática e configurar a Site URL do Supabase Auth assim que a URL final existir.
