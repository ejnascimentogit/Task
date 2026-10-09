-- Painel multi-workspace (estilo Notion) — schema completo
-- Baseado em supabase-schema.sql (referência), adaptado para múltiplos workspaces
-- isolados no mesmo banco, cada um com seu perfil_tipo (pessoal | equipe | projeto).
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em "Run".

-- ══════════════════════════════════════════════════════════════
-- 1. WORKSPACES E MEMBROS
-- ══════════════════════════════════════════════════════════════

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  perfil_tipo text not null check (perfil_tipo in ('pessoal','equipe','projeto')),
  owner_id uuid not null references auth.users(id),
  invite_code text not null unique default substr(md5(random()::text || clock_timestamp()::text), 1, 8),
  entidade_label text,
  cor_destaque text not null default '#00FF7A',
  cor_fundo text not null default '#F4F5F3',
  codigo_automatico boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.workspace_membros (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid references auth.users(id),
  email text not null,
  nome text default '',
  role text not null default 'membro' check (role in ('admin','membro')),
  status text not null default 'pendente' check (status in ('pendente','ativo')),
  apenas_visualizacao boolean not null default false,
  created_at timestamptz not null default now()
);

create unique index idx_workspace_membros_email on public.workspace_membros (workspace_id, lower(email));
create index idx_workspace_membros_user on public.workspace_membros (user_id);
create index idx_workspace_membros_workspace on public.workspace_membros (workspace_id);

-- ══════════════════════════════════════════════════════════════
-- 2. TABELAS DE DOMÍNIO (adaptadas de supabase-schema.sql, todas com workspace_id)
-- ══════════════════════════════════════════════════════════════

create table public.entidades (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  codigo text,
  nome text not null,
  responsavel text default '',
  etapa text not null default 'kickoff',
  fase text not null default 'implantacao' check (fase in ('implantacao','base')),
  saude text not null default 'verde' check (saude in ('verde','amarelo','vermelho')),
  saude_motivo text default '',
  observacao text default '',
  inicio date not null default current_date,
  ultimo_contato date,
  proximo_contato date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, codigo)
);

create table public.contatos_entidade (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  entidade_id uuid not null references public.entidades(id) on delete cascade,
  nome text not null,
  telefone text default '',
  cargo text default '',
  created_at timestamptz not null default now()
);

create table public.pendencias (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  entidade_id uuid not null references public.entidades(id) on delete cascade,
  texto text not null,
  responsavel text not null check (responsavel in ('entidade','equipe')),
  feito boolean not null default false,
  observacao text default '',
  created_at timestamptz not null default now()
);

create table public.historico (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  entidade_id uuid not null references public.entidades(id) on delete cascade,
  data date not null default current_date,
  texto text not null,
  created_at timestamptz not null default now()
);

create table public.etapas (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  id text not null,
  nome text not null,
  cor text not null default '#3B82F6',
  ordem int not null,
  created_at timestamptz not null default now(),
  primary key (workspace_id, id)
);

create table public.tipos_agendamento (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  id text not null,
  nome text not null,
  icone text not null default '📌',
  ordem int not null,
  created_at timestamptz not null default now(),
  primary key (workspace_id, id)
);

create table public.agendamentos (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  entidade_id uuid references public.entidades(id) on delete set null,
  entidade_nome text default '',
  titulo text not null,
  tipo text not null default 'reuniao',
  data date not null,
  hora time,
  observacao text default '',
  feito boolean not null default false,
  responsavel text default '',
  participantes text[] default '{}',
  reagendado_de date,
  created_at timestamptz not null default now()
);

-- Raias do Kanban editáveis por workspace. "concluida" é reservada/fixa no app (não vive
-- nesta tabela) por causa da regra de resolução obrigatória + histórico automático.
create table public.kanban_colunas (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  id text not null,
  nome text not null,
  ordem int not null,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (workspace_id, id)
);

create table public.atividades (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  responsavel text not null,
  criado_por text default '',
  titulo text not null default '',
  descricao text default '',
  entidade_nome text default '',
  label text check (label in ('red','orange','yellow','blue') or label is null),
  coluna text not null default 'afazer',
  urgente boolean not null default false,
  cancelado boolean not null default false,
  resolucao text default '',
  participantes text[] default '{}',
  concluido_em date,
  ordem int not null default 0,
  created_at timestamptz not null default now()
);

-- Liga um agendamento à atividade criada a partir dele (botão "Criar Atividade" no modal de
-- Agendamento), evitando duplicar o mesmo assunto/observação em atividades manualmente.
alter table public.agendamentos add column atividade_id uuid references public.atividades(id) on delete set null;

create table public.atividade_imagens (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  atividade_id uuid not null references public.atividades(id) on delete cascade,
  path text not null,
  url text not null,
  created_at timestamptz not null default now()
);

create table public.treinamentos_etapas (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  entidade_id uuid not null references public.entidades(id) on delete cascade,
  titulo text not null,
  analista text default '',
  usuario_chave text default '',
  link_reuniao text default '',
  data date,
  hora time,
  data_termino date,
  concluido boolean not null default false,
  lembrete_ativo boolean not null default false,
  ordem int not null default 0,
  created_at timestamptz not null default now()
);

create table public.treinamentos_padrao (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  id text not null,
  nome text not null,
  ordem int not null,
  created_at timestamptz not null default now(),
  primary key (workspace_id, id)
);

create table public.treinamento_etapa_atividades (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  etapa_id uuid not null references public.treinamentos_etapas(id) on delete cascade,
  texto text not null,
  feito boolean not null default false,
  ordem int not null default 0,
  created_at timestamptz not null default now()
);

create table public.feriados_datas (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  nome text not null,
  mes int not null check (mes between 1 and 12),
  dia int not null check (dia between 1 and 31),
  tipo text not null default 'comercial' check (tipo in ('estadual','municipal','comercial')),
  created_at timestamptz not null default now()
);

-- índices
create index idx_entidades_workspace on public.entidades(workspace_id);
create index idx_contatos_entidade_entidade on public.contatos_entidade(entidade_id);
create index idx_contatos_entidade_workspace on public.contatos_entidade(workspace_id);
create index idx_pendencias_entidade on public.pendencias(entidade_id);
create index idx_pendencias_workspace on public.pendencias(workspace_id);
create index idx_historico_entidade on public.historico(entidade_id);
create index idx_historico_workspace on public.historico(workspace_id);
create index idx_etapas_workspace on public.etapas(workspace_id);
create index idx_tipos_agendamento_workspace on public.tipos_agendamento(workspace_id);
create index idx_agendamentos_entidade on public.agendamentos(entidade_id);
create index idx_agendamentos_workspace on public.agendamentos(workspace_id);
create index idx_agendamentos_data on public.agendamentos(data);
create index idx_atividades_workspace on public.atividades(workspace_id);
create index idx_atividades_responsavel on public.atividades(responsavel);
create index idx_atividades_concluido_em on public.atividades(concluido_em);
create index idx_atividade_imagens_atividade on public.atividade_imagens(atividade_id);
create index idx_atividade_imagens_workspace on public.atividade_imagens(workspace_id);
create index idx_treinamentos_etapas_entidade on public.treinamentos_etapas(entidade_id);
create index idx_treinamentos_etapas_workspace on public.treinamentos_etapas(workspace_id);
create index idx_trein_etapa_ativ_etapa on public.treinamento_etapa_atividades(etapa_id);
create index idx_trein_etapa_ativ_workspace on public.treinamento_etapa_atividades(workspace_id);
create index idx_feriados_datas_workspace on public.feriados_datas(workspace_id);

-- ══════════════════════════════════════════════════════════════
-- 3. FUNÇÕES AUXILIARES DE AUTORIZAÇÃO (usadas nas policies de RLS)
-- ══════════════════════════════════════════════════════════════

create or replace function public.is_member(ws_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.workspace_membros
    where workspace_id = ws_id and user_id = auth.uid() and status = 'ativo'
  );
$$;

create or replace function public.is_admin(ws_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.workspace_membros
    where workspace_id = ws_id and user_id = auth.uid() and status = 'ativo' and role = 'admin'
  );
$$;

-- ══════════════════════════════════════════════════════════════
-- 4. TRIGGERS DE ONBOARDING
-- ══════════════════════════════════════════════════════════════

-- Ao criar um workspace, o criador vira automaticamente membro admin dele.
-- (Sem isto, ninguém conseguiria inserir a própria linha em workspace_membros,
-- já que a policy de insert ali exige já ser admin do workspace.)
create or replace function public.handle_new_workspace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_nome text;
begin
  select email, coalesce(raw_user_meta_data->>'nome', split_part(email, '@', 1))
    into v_email, v_nome
  from auth.users where id = new.owner_id;

  insert into public.workspace_membros (workspace_id, user_id, email, nome, role, status)
  values (new.id, new.owner_id, v_email, v_nome, 'admin', 'ativo');

  return new;
end;
$$;

drop trigger if exists on_workspace_created on public.workspaces;
create trigger on_workspace_created
after insert on public.workspaces
for each row execute function public.handle_new_workspace();

-- Ao criar a conta (signup), ativa automaticamente qualquer convite pendente
-- que já exista com o mesmo e-mail em algum workspace.
create or replace function public.activate_pending_invites()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.workspace_membros
     set user_id = new.id, status = 'ativo'
   where lower(email) = lower(new.email) and status = 'pendente';
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_invites on auth.users;
create trigger on_auth_user_created_invites
after insert on auth.users
for each row execute function public.activate_pending_invites();

-- Ativa convites pendentes do usuário logado. O trigger acima só cobre quem se cadastra
-- DEPOIS de já ter sido convidado; isto cobre o caso de convidar alguém que já tinha conta
-- antes do convite existir — o app chama esta função uma vez a cada login.
create or replace function public.accept_pending_invites()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.workspace_membros
     set user_id = auth.uid(), status = 'ativo'
   where lower(email) = lower((select email from auth.users where id = auth.uid()))
     and status = 'pendente';
end;
$$;

-- Entrar num workspace por código de convite (link compartilhável).
-- É uma função (não uma policy de insert direta) porque a policy não teria como
-- validar "o usuário realmente conhece o código" sem abrir insert livre em workspace_membros.
create or replace function public.join_workspace_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workspace_id uuid;
  v_email text;
  v_nome text;
begin
  select id into v_workspace_id from public.workspaces where invite_code = p_code;
  if v_workspace_id is null then
    raise exception 'Código de convite inválido';
  end if;

  select email, coalesce(raw_user_meta_data->>'nome', split_part(email, '@', 1))
    into v_email, v_nome
  from auth.users where id = auth.uid();

  insert into public.workspace_membros (workspace_id, user_id, email, nome, role, status)
  values (v_workspace_id, auth.uid(), v_email, v_nome, 'membro', 'ativo')
  on conflict (workspace_id, lower(email))
  do update set user_id = excluded.user_id, status = 'ativo';

  return v_workspace_id;
end;
$$;

-- ══════════════════════════════════════════════════════════════
-- 5. RLS — real, isolada por workspace (não é a RLS permissiva do sistema de referência,
--    necessária aqui porque múltiplos workspaces/donos de dados compartilham o mesmo banco)
-- ══════════════════════════════════════════════════════════════

alter table public.workspaces enable row level security;
alter table public.workspace_membros enable row level security;
alter table public.entidades enable row level security;
alter table public.contatos_entidade enable row level security;
alter table public.pendencias enable row level security;
alter table public.historico enable row level security;
alter table public.etapas enable row level security;
alter table public.kanban_colunas enable row level security;
alter table public.tipos_agendamento enable row level security;
alter table public.agendamentos enable row level security;
alter table public.atividades enable row level security;
alter table public.atividade_imagens enable row level security;
alter table public.treinamentos_etapas enable row level security;
alter table public.treinamentos_padrao enable row level security;
alter table public.treinamento_etapa_atividades enable row level security;
alter table public.feriados_datas enable row level security;

-- "owner_id = auth.uid()" cobre o instante do INSERT: o RETURNING de um insert reavalia a
-- policy de SELECT, e a linha de workspace_membros que o trigger cria só fica visível a essa
-- reavaliação de forma pouco confiável — checar a coluna owner_id direto evita essa corrida.
create policy "select own workspaces" on public.workspaces for select using (is_member(id) or owner_id = auth.uid());
create policy "insert own workspace" on public.workspaces for insert with check (owner_id = auth.uid());
create policy "update admin workspace" on public.workspaces for update using (is_admin(id)) with check (is_admin(id));
create policy "delete admin workspace" on public.workspaces for delete using (is_admin(id));

create policy "select membros" on public.workspace_membros for select using (is_member(workspace_id));
create policy "insert membros admin" on public.workspace_membros for insert with check (is_admin(workspace_id));
create policy "update membros admin" on public.workspace_membros for update using (is_admin(workspace_id)) with check (is_admin(workspace_id));
create policy "delete membros admin" on public.workspace_membros for delete using (is_admin(workspace_id));
create policy "sair do workspace" on public.workspace_membros for delete using (user_id = auth.uid());

create policy "workspace access entidades" on public.entidades for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access contatos_entidade" on public.contatos_entidade for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access pendencias" on public.pendencias for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access historico" on public.historico for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access etapas" on public.etapas for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access kanban_colunas" on public.kanban_colunas for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access tipos_agendamento" on public.tipos_agendamento for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access agendamentos" on public.agendamentos for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access atividades" on public.atividades for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access atividade_imagens" on public.atividade_imagens for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access treinamentos_etapas" on public.treinamentos_etapas for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access treinamentos_padrao" on public.treinamentos_padrao for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access treinamento_etapa_atividades" on public.treinamento_etapa_atividades for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy "workspace access feriados_datas" on public.feriados_datas for all using (is_member(workspace_id)) with check (is_member(workspace_id));

-- ══════════════════════════════════════════════════════════════
-- 6. STORAGE — bucket público (mesmo padrão do sistema de referência), mas upload/exclusão
--    exigem que o primeiro segmento do path seja um workspace_id do qual o usuário é membro.
--    O app deve gravar em `${workspaceId}/${atividadeId}/${arquivo}`.
--    Leitura via URL pública continua sem checagem (mesma dívida técnica do original —
--    aceitável porque o path carrega um workspace_id/atividade_id em uuid, não listável).
-- ══════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public) values ('atividade-imagens', 'atividade-imagens', true)
on conflict (id) do nothing;

create policy "public select atividade-imagens" on storage.objects for select using (bucket_id = 'atividade-imagens');

create policy "ws insert atividade-imagens" on storage.objects for insert with check (
  bucket_id = 'atividade-imagens' and public.is_member((storage.foldername(name))[1]::uuid)
);

create policy "ws delete atividade-imagens" on storage.objects for delete using (
  bucket_id = 'atividade-imagens' and public.is_member((storage.foldername(name))[1]::uuid)
);

-- ══════════════════════════════════════════════════════════════
-- FASES 2 E 3 (novidades do Painel de Implantação): colunas aditivas, busca full-text e estrutura (desligada) da busca com IA
-- Tudo idempotente e só inclui: nada existente é removido ou alterado.
-- ══════════════════════════════════════════════════════════════

-- Pendências: posição manual (arrastar pra reordenar) e flag da Lâmina
alter table public.pendencias add column if not exists ordem integer;
alter table public.pendencias add column if not exists mostrar_lamina boolean not null default true;

-- Contato do dia por canal (ligacao | mensagem | email | reuniao)
alter table public.entidades add column if not exists ultimo_contato_canal text;

-- ── Busca full-text dentro de UM workspace ────────────────────────────────────────────────────
-- Sem security definer de propósito: roda com o papel de quem chamou, então a RLS (is_member) filtra sozinha.
-- Busca nas notas da entidade, nas atividades (título, descrição e resolução; abertas e concluídas, não canceladas)
-- e nas pendências (texto e observação). Funciona também no perfil Pessoal (que não tem entidades): as atividades
-- entram pelo próprio texto, sem depender de entidade.
drop function if exists public.buscar_workspace(uuid, text);
create function public.buscar_workspace(p_workspace_id uuid, p_termo text)
returns table(
  id uuid, nome text, origem text, titulo text, responsavel text,
  data date, coluna text, trecho text, rank real
)
language sql
stable
set search_path = public
as $$
  with termo as (
    select websearch_to_tsquery('portuguese', p_termo) as q
  ),
  ficha as (
    select
      e.id as r_id, e.nome as r_nome, 'ficha'::text as r_origem, null::text as r_titulo, null::text as r_resp,
      null::date as r_data, null::text as r_coluna,
      ts_headline('portuguese', coalesce(e.observacao, ''), termo.q,
        'StartSel=<mark>,StopSel=</mark>,MaxWords=35,MinWords=15,MaxFragments=3,FragmentDelimiter= […] ') as r_trecho,
      ts_rank(to_tsvector('portuguese', coalesce(e.observacao, '')), termo.q) as r_rank,
      1 as r_pos
    from public.entidades e, termo
    where e.workspace_id = p_workspace_id
      and to_tsvector('portuguese', coalesce(e.observacao, '')) @@ termo.q
  ),
  ativ as (
    select
      (select e.id from public.entidades e
        where e.workspace_id = a.workspace_id and lower(e.nome) = lower(a.entidade_nome) limit 1) as r_id,
      coalesce(a.entidade_nome, '') as r_nome, 'atividade'::text as r_origem, a.titulo as r_titulo, a.responsavel as r_resp,
      a.concluido_em as r_data, a.coluna as r_coluna,
      ts_headline('portuguese', btrim(coalesce(a.descricao, '') || E'\n' || coalesce(a.resolucao, '')), termo.q,
        'StartSel=<mark>,StopSel=</mark>,MaxWords=40,MinWords=10,MaxFragments=2,FragmentDelimiter= […] ') as r_trecho,
      ts_rank(to_tsvector('portuguese', coalesce(a.titulo, '') || ' ' || coalesce(a.descricao, '') || ' ' || coalesce(a.resolucao, '')), termo.q) as r_rank,
      row_number() over (
        partition by lower(coalesce(a.entidade_nome, ''))
        order by ts_rank(to_tsvector('portuguese', coalesce(a.titulo, '') || ' ' || coalesce(a.descricao, '') || ' ' || coalesce(a.resolucao, '')), termo.q) desc
      ) as r_pos
    from public.atividades a, termo
    where a.workspace_id = p_workspace_id
      and not a.cancelado
      and to_tsvector('portuguese', coalesce(a.titulo, '') || ' ' || coalesce(a.descricao, '') || ' ' || coalesce(a.resolucao, '')) @@ termo.q
  ),
  pend as (
    select
      p.entidade_id as r_id, e.nome as r_nome, 'pendencia'::text as r_origem, p.texto as r_titulo, p.responsavel as r_resp,
      null::date as r_data, case when p.feito then 'feita' else 'aberta' end as r_coluna,
      ts_headline('portuguese', coalesce(p.observacao, ''), termo.q,
        'StartSel=<mark>,StopSel=</mark>,MaxWords=35,MinWords=10,MaxFragments=1,FragmentDelimiter= […] ') as r_trecho,
      ts_rank(to_tsvector('portuguese', coalesce(p.texto, '') || ' ' || coalesce(p.observacao, '')), termo.q) as r_rank,
      row_number() over (
        partition by p.entidade_id
        order by ts_rank(to_tsvector('portuguese', coalesce(p.texto, '') || ' ' || coalesce(p.observacao, '')), termo.q) desc
      ) as r_pos
    from public.pendencias p
    join public.entidades e on e.id = p.entidade_id, termo
    where p.workspace_id = p_workspace_id
      and to_tsvector('portuguese', coalesce(p.texto, '') || ' ' || coalesce(p.observacao, '')) @@ termo.q
  )
  select u.r_id, u.r_nome, u.r_origem, u.r_titulo, u.r_resp, u.r_data, u.r_coluna, u.r_trecho, u.r_rank
  from (
    select * from ficha
    union all select * from ativ
    union all select * from pend
  ) u
  where u.r_pos <= 3
  order by u.r_rank desc;
$$;
grant execute on function public.buscar_workspace(uuid, text) to authenticated;

-- ── ESTRUTURA DA BUSCA COM IA (DESLIGADA: nada disso gasta nada até alguém ligar e publicar a Edge Function) ──
-- A chave da Anthropic é do dono do app e vale pra TODOS os workspaces, então a liga NÃO fica numa coluna que um
-- admin de workspace consiga editar: fica numa tabela só de leitura pros membros, sem policy de escrita
-- (só o dono do app liga/desliga, pelo SQL Editor, com a service role).
create table if not exists public.busca_ia_config (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  ativo boolean not null default false,
  limite_mensal_usd numeric(10,2) not null default 1.00,
  updated_at timestamptz not null default now()
);
alter table public.busca_ia_config enable row level security;
drop policy if exists "membros leem busca_ia_config" on public.busca_ia_config;
create policy "membros leem busca_ia_config" on public.busca_ia_config for select using (is_member(workspace_id));

-- Uma linha por pergunta respondida pela IA (gravada só pela Edge Function, com a service role: membro só lê,
-- assim ninguém zera o contador do limite mensal).
create table if not exists public.busca_ia_uso (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid references auth.users(id),
  pessoa text,
  termo text not null,
  tokens_input int not null default 0,
  tokens_output int not null default 0,
  custo_estimado numeric(10,6) not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_busca_ia_uso_workspace on public.busca_ia_uso(workspace_id, created_at);
alter table public.busca_ia_uso enable row level security;
drop policy if exists "membros leem busca_ia_uso" on public.busca_ia_uso;
create policy "membros leem busca_ia_uso" on public.busca_ia_uso for select using (is_member(workspace_id));

-- ══════════════════════════════════════════════════════════════
-- CRONOGRAMA DO CLIENTE (só perfil Gestão de Projeto): estrutura por projeto + portal do cliente (/cronograma)
-- Cada projeto (entidade) tem etapas > itens > checklist. O cliente entra no portal com um login próprio (conta sintética
-- usuario@cliente.taskfull.invalid criada pela Edge Function cronograma-criar-login) e só enxerga o próprio projeto.
-- ══════════════════════════════════════════════════════════════
create table if not exists public.cronograma_acessos (
  entidade_id uuid primary key references public.entidades(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid unique references auth.users(id) on delete set null,
  usuario text not null unique,
  senha_trocada boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.cronograma_etapas (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  entidade_id uuid not null references public.entidades(id) on delete cascade,
  nome text not null,
  ordem int not null default 0,
  bloqueada boolean not null default false,
  nota_bloqueio text default '',
  created_at timestamptz not null default now()
);
create table if not exists public.cronograma_itens (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  etapa_id uuid not null references public.cronograma_etapas(id) on delete cascade,
  nome text not null,
  ordem int not null default 0,
  responsavel text not null default 'equipe' check (responsavel in ('cliente','equipe')),
  baseline text default '',
  data_validacao date,
  status text not null default 'pendente' check (status in ('pendente','concluido')),
  escopo text default '',
  created_at timestamptz not null default now()
);
create table if not exists public.cronograma_subitens (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  item_id uuid not null references public.cronograma_itens(id) on delete cascade,
  grupo text default '',
  nome text not null,
  ordem int not null default 0,
  feito boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.cronograma_log (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  entidade_id uuid not null references public.entidades(id) on delete cascade,
  item_id uuid references public.cronograma_itens(id) on delete set null,
  item_nome text,
  status_antes text, status_depois text,
  baseline_antes text, baseline_depois text,
  data_validacao_antes date, data_validacao_depois date,
  created_at timestamptz not null default now()
);
create index if not exists idx_cron_etapas_entidade on public.cronograma_etapas(entidade_id);
create index if not exists idx_cron_itens_etapa on public.cronograma_itens(etapa_id);
create index if not exists idx_cron_subitens_item on public.cronograma_subitens(item_id);
create index if not exists idx_cron_log_entidade on public.cronograma_log(entidade_id, created_at);
create index if not exists idx_cron_acessos_workspace on public.cronograma_acessos(workspace_id);

alter table public.cronograma_acessos enable row level security;
alter table public.cronograma_etapas enable row level security;
alter table public.cronograma_itens enable row level security;
alter table public.cronograma_subitens enable row level security;
alter table public.cronograma_log enable row level security;

create or replace function public.cronograma_entidade_do_usuario()
returns uuid language sql stable security definer set search_path = public
as $$ select entidade_id from public.cronograma_acessos where user_id = auth.uid(); $$;

-- Membros do workspace gerenciam tudo; o CLIENTE só lê o próprio projeto (e só altera item pela função abaixo).
-- Logins (cronograma_acessos) só são escritos pela Edge Function, com a service role. O log só é escrito pela função de atualização.
drop policy if exists "membros leem cronograma_acessos" on public.cronograma_acessos;
create policy "membros leem cronograma_acessos" on public.cronograma_acessos for select using (is_member(workspace_id));
drop policy if exists "membros gerenciam cronograma_etapas" on public.cronograma_etapas;
create policy "membros gerenciam cronograma_etapas" on public.cronograma_etapas for all using (is_member(workspace_id)) with check (is_member(workspace_id));
drop policy if exists "cliente le as proprias etapas" on public.cronograma_etapas;
create policy "cliente le as proprias etapas" on public.cronograma_etapas for select using (entidade_id = public.cronograma_entidade_do_usuario());
drop policy if exists "membros gerenciam cronograma_itens" on public.cronograma_itens;
create policy "membros gerenciam cronograma_itens" on public.cronograma_itens for all using (is_member(workspace_id)) with check (is_member(workspace_id));
drop policy if exists "cliente le os proprios itens" on public.cronograma_itens;
create policy "cliente le os proprios itens" on public.cronograma_itens for select using (
  etapa_id in (select id from public.cronograma_etapas where entidade_id = public.cronograma_entidade_do_usuario()));
drop policy if exists "membros gerenciam cronograma_subitens" on public.cronograma_subitens;
create policy "membros gerenciam cronograma_subitens" on public.cronograma_subitens for all using (is_member(workspace_id)) with check (is_member(workspace_id));
drop policy if exists "cliente le os proprios subitens" on public.cronograma_subitens;
create policy "cliente le os proprios subitens" on public.cronograma_subitens for select using (
  item_id in (select i.id from public.cronograma_itens i join public.cronograma_etapas e on e.id = i.etapa_id
              where e.entidade_id = public.cronograma_entidade_do_usuario()));
drop policy if exists "membros leem cronograma_log" on public.cronograma_log;
create policy "membros leem cronograma_log" on public.cronograma_log for select using (is_member(workspace_id));

create or replace function public.cronograma_meu_projeto()
returns table(entidade_id uuid, nome text, workspace_nome text, senha_trocada boolean)
language sql stable security definer set search_path = public
as $$
  select a.entidade_id, e.nome, w.nome, a.senha_trocada
  from public.cronograma_acessos a
  join public.entidades e on e.id = a.entidade_id
  join public.workspaces w on w.id = a.workspace_id
  where a.user_id = auth.uid();
$$;
grant execute on function public.cronograma_meu_projeto() to authenticated;

create or replace function public.cronograma_marcar_senha_trocada()
returns void language sql security definer set search_path = public
as $$ update public.cronograma_acessos set senha_trocada = true where user_id = auth.uid(); $$;
grant execute on function public.cronograma_marcar_senha_trocada() to authenticated;

-- ÚNICO caminho do cliente alterar um item: valida que o item é do projeto dele E que está marcado como do cliente; grava o log sempre.
create or replace function public.atualizar_item_cronograma_cliente(p_item_id uuid, p_status text, p_baseline text, p_data_validacao date)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_entidade uuid := public.cronograma_entidade_do_usuario();
  v_item record;
begin
  if v_entidade is null then raise exception 'Sem permissão.'; end if;
  if p_status not in ('pendente','concluido') then raise exception 'Status inválido.'; end if;
  if length(coalesce(p_baseline, '')) > 60 then raise exception 'Baseline muito longo.'; end if;

  select i.id, i.nome, i.status, i.responsavel, i.baseline, i.data_validacao, i.workspace_id, e.entidade_id
    into v_item
  from public.cronograma_itens i join public.cronograma_etapas e on e.id = i.etapa_id
  where i.id = p_item_id;

  -- checar "is null" à parte ANTES do "<>": comparar com null dá null (não true) e um "if null" não dispara.
  if v_item.id is null or v_item.entidade_id is distinct from v_entidade then raise exception 'Sem permissão para alterar este item.'; end if;
  if v_item.responsavel <> 'cliente' then raise exception 'Este item é de responsabilidade da equipe: só ela pode alterá-lo.'; end if;

  insert into public.cronograma_log (workspace_id, entidade_id, item_id, item_nome, status_antes, status_depois, baseline_antes, baseline_depois, data_validacao_antes, data_validacao_depois)
  values (v_item.workspace_id, v_entidade, v_item.id, v_item.nome, v_item.status, p_status, v_item.baseline, p_baseline, v_item.data_validacao, p_data_validacao);

  update public.cronograma_itens set status = p_status, baseline = p_baseline, data_validacao = p_data_validacao where id = p_item_id;
end; $$;
grant execute on function public.atualizar_item_cronograma_cliente(uuid, text, text, date) to authenticated;

-- Copia a estrutura de um projeto para outro projeto SEM cronograma (status e datas voltam em branco). Checagem de membro à mão (security definer ignora a RLS).
create or replace function public.duplicar_cronograma(p_origem uuid, p_destino uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_ws_o uuid; v_ws_d uuid; r_etapa record; v_nova uuid; r_item record; v_novo_item uuid; r_sub record;
begin
  select workspace_id into v_ws_o from public.entidades where id = p_origem;
  select workspace_id into v_ws_d from public.entidades where id = p_destino;
  if v_ws_o is null or v_ws_d is null or v_ws_o <> v_ws_d then raise exception 'Projetos inválidos.'; end if;
  if not public.is_member(v_ws_d) then raise exception 'Sem permissão.'; end if;
  if exists (select 1 from public.cronograma_etapas where entidade_id = p_destino) then raise exception 'O projeto de destino já tem cronograma.'; end if;
  for r_etapa in select * from public.cronograma_etapas where entidade_id = p_origem order by ordem loop
    insert into public.cronograma_etapas (workspace_id, entidade_id, nome, ordem, bloqueada, nota_bloqueio)
    values (v_ws_d, p_destino, r_etapa.nome, r_etapa.ordem, r_etapa.bloqueada, r_etapa.nota_bloqueio) returning id into v_nova;
    for r_item in select * from public.cronograma_itens where etapa_id = r_etapa.id order by ordem loop
      insert into public.cronograma_itens (workspace_id, etapa_id, nome, ordem, responsavel, baseline, data_validacao, status, escopo)
      values (v_ws_d, v_nova, r_item.nome, r_item.ordem, r_item.responsavel, r_item.baseline, null, 'pendente', r_item.escopo) returning id into v_novo_item;
      for r_sub in select * from public.cronograma_subitens where item_id = r_item.id order by ordem loop
        insert into public.cronograma_subitens (workspace_id, item_id, grupo, nome, ordem, feito)
        values (v_ws_d, v_novo_item, r_sub.grupo, r_sub.nome, r_sub.ordem, false);
      end loop;
    end loop;
  end loop;
end; $$;
grant execute on function public.duplicar_cronograma(uuid, uuid) to authenticated;

-- Endurecimento: contas de cliente (e-mail sintético @cliente.taskfull.invalid) não criam nem entram em workspaces.
create or replace function public.join_workspace_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workspace_id uuid;
  v_email text;
  v_nome text;
begin
  select id into v_workspace_id from public.workspaces where invite_code = p_code;
  if v_workspace_id is null then
    raise exception 'Código de convite inválido';
  end if;

  select email, coalesce(raw_user_meta_data->>'nome', split_part(email, '@', 1))
    into v_email, v_nome
  from auth.users where id = auth.uid();

  if v_email like '%@cliente.taskfull.invalid' then
    raise exception 'Contas de cliente do cronograma não entram em workspaces.';
  end if;

  insert into public.workspace_membros (workspace_id, user_id, email, nome, role, status)
  values (v_workspace_id, auth.uid(), v_email, v_nome, 'membro', 'ativo')
  on conflict (workspace_id, lower(email))
  do update set user_id = excluded.user_id, status = 'ativo';

  return v_workspace_id;
end;
$$;

drop policy if exists "insert own workspace" on public.workspaces;
create policy "insert own workspace" on public.workspaces for insert
  with check (owner_id = auth.uid() and coalesce(auth.jwt() ->> 'email', '') not like '%@cliente.taskfull.invalid');

-- ── Colunas novas em entidades (analista responsável e previsão de entrega, perfil Gestão de Projeto) ──
alter table public.entidades add column if not exists analista_responsavel text default '';
alter table public.entidades add column if not exists previsao_entrega date;

-- ══════════════════════════════════════════════════════════════
-- ASSESSOR PESSOAL (perfil Pessoal) — canal Telegram. Aplicado em produção em 2026-10-07.
-- Aditivo e idempotente. Ver CLAUDE.md, seção "Assessor pessoal".
-- ══════════════════════════════════════════════════════════════
create table if not exists public.assessor_vinculos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  canal text not null default 'telegram',
  chat_id bigint,
  telegram_usuario text,
  codigo text,
  codigo_expira_em timestamptz,
  lembrete_minutos integer not null default 60,
  ativo boolean not null default true,
  vinculado_em timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, canal)
);
alter table public.assessor_vinculos add column if not exists limite_mensal_usd numeric not null default 3.00;
create unique index if not exists assessor_vinculos_chat_uidx on public.assessor_vinculos (canal, chat_id) where chat_id is not null;
create unique index if not exists assessor_vinculos_codigo_uidx on public.assessor_vinculos (codigo) where codigo is not null;
alter table public.assessor_vinculos enable row level security;
drop policy if exists assessor_vinculos_select on public.assessor_vinculos;
create policy assessor_vinculos_select on public.assessor_vinculos for select using (user_id = auth.uid());
-- Sem policy de update: o navegador só altera o vínculo pelas funções abaixo.
drop policy if exists assessor_vinculos_update on public.assessor_vinculos;

create table if not exists public.assessor_mensagens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  canal text not null default 'telegram',
  papel text not null check (papel in ('user','assistant')),
  conteudo text not null,
  created_at timestamptz not null default now()
);
create index if not exists assessor_mensagens_user_idx on public.assessor_mensagens (user_id, created_at desc);
alter table public.assessor_mensagens enable row level security;
drop policy if exists assessor_mensagens_select on public.assessor_mensagens;
create policy assessor_mensagens_select on public.assessor_mensagens for select using (user_id = auth.uid());
drop policy if exists assessor_mensagens_delete on public.assessor_mensagens;
create policy assessor_mensagens_delete on public.assessor_mensagens for delete using (user_id = auth.uid());

create table if not exists public.assessor_uso (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  canal text not null default 'telegram',
  modelo text not null,
  tokens_input integer not null default 0,
  tokens_output integer not null default 0,
  tokens_cache_leitura integer not null default 0,
  tokens_cache_escrita integer not null default 0,
  custo_estimado_usd numeric not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists assessor_uso_user_idx on public.assessor_uso (user_id, created_at desc);
alter table public.assessor_uso enable row level security;
drop policy if exists assessor_uso_select on public.assessor_uso;
create policy assessor_uso_select on public.assessor_uso for select using (user_id = auth.uid());

create table if not exists public.assessor_lembretes_enviados (
  agendamento_id uuid not null references public.agendamentos(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  enviado_em timestamptz not null default now(),
  primary key (agendamento_id, user_id)
);
alter table public.assessor_lembretes_enviados enable row level security;

create or replace function public.assessor_gerar_codigo(p_workspace_id uuid)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  v_uid uuid := auth.uid();
  v_codigo text;
begin
  if v_uid is null then raise exception 'Não autenticado'; end if;
  if not exists (
    select 1 from workspaces w join workspace_membros m on m.workspace_id = w.id
    where w.id = p_workspace_id and w.perfil_tipo = 'pessoal' and m.user_id = v_uid and m.status = 'ativo'
  ) then
    raise exception 'O assessor só está disponível no seu perfil Pessoal';
  end if;
  v_codigo := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into assessor_vinculos (user_id, workspace_id, canal, codigo, codigo_expira_em)
  values (v_uid, p_workspace_id, 'telegram', v_codigo, now() + interval '15 minutes')
  on conflict (user_id, canal) do update
    set workspace_id = excluded.workspace_id, codigo = excluded.codigo,
        codigo_expira_em = excluded.codigo_expira_em, ativo = true;
  return v_codigo;
end;
$fn$;
revoke all on function public.assessor_gerar_codigo(uuid) from public, anon;
grant execute on function public.assessor_gerar_codigo(uuid) to authenticated;

create or replace function public.assessor_desconectar()
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  delete from assessor_mensagens where user_id = auth.uid() and canal = 'telegram';
  delete from assessor_vinculos where user_id = auth.uid() and canal = 'telegram';
end;
$fn$;
revoke all on function public.assessor_desconectar() from public, anon;
grant execute on function public.assessor_desconectar() to authenticated;

create or replace function public.assessor_definir_lembrete(p_minutos integer)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  if p_minutos not in (15, 30, 60, 120) then raise exception 'Escolha 15, 30, 60 ou 120 minutos'; end if;
  update assessor_vinculos set lembrete_minutos = p_minutos where user_id = auth.uid() and canal = 'telegram';
end;
$fn$;
revoke all on function public.assessor_definir_lembrete(integer) from public, anon;
grant execute on function public.assessor_definir_lembrete(integer) to authenticated;

create or replace function public.assessor_lembretes_pendentes()
returns table (agendamento_id uuid, user_id uuid, chat_id bigint, titulo text, data date, hora time, minutos_faltando integer)
language sql security definer set search_path = public as $fn$
  select a.id, v.user_id, v.chat_id, a.titulo, a.data, a.hora,
         ceil(extract(epoch from (((a.data + a.hora) at time zone 'America/Sao_Paulo') - now())) / 60)::int
  from assessor_vinculos v
  join agendamentos a on a.workspace_id = v.workspace_id
  where v.canal = 'telegram' and v.ativo and v.chat_id is not null
    and a.feito = false and a.hora is not null
    and ((a.data + a.hora) at time zone 'America/Sao_Paulo') > now()
    and ((a.data + a.hora) at time zone 'America/Sao_Paulo') <= now() + make_interval(mins => v.lembrete_minutos)
    and not exists (select 1 from assessor_lembretes_enviados e where e.agendamento_id = a.id and e.user_id = v.user_id);
$fn$;
revoke all on function public.assessor_lembretes_pendentes() from public, anon, authenticated;
grant execute on function public.assessor_lembretes_pendentes() to service_role;

-- Agendador (rodar uma vez; a chave no Authorization é a anon pública, a mesma do index.html):
create extension if not exists pg_net;
create extension if not exists pg_cron;
-- select cron.schedule('assessor-lembretes', '* * * * *', $c$ select net.http_post(
--   url := 'https://dubbmmjtbunzmdmfbbja.supabase.co/functions/v1/assessor-lembretes',
--   headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer <anon key>'),
--   body := '{}'::jsonb); $c$);
-- select cron.schedule('assessor-limpar-mensagens', '15 3 * * *',
--   $c$ delete from public.assessor_mensagens where created_at < now() - interval '30 days'; $c$);

-- ══════════════════════════════════════════════════════════════
-- Atualização automática (2026-10-09): Realtime em Agenda e Atividades
-- ══════════════════════════════════════════════════════════════
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'agendamentos') then
    alter publication supabase_realtime add table public.agendamentos;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'atividades') then
    alter publication supabase_realtime add table public.atividades;
  end if;
end $$;

-- ══════════════════════════════════════════════════════════════
-- Assessor: áudio, busca na web e vocabulário pessoal (2026-10-09)
-- ══════════════════════════════════════════════════════════════
alter table public.assessor_uso add column if not exists audio_segundos integer not null default 0;
alter table public.assessor_uso add column if not exists buscas_web integer not null default 0;

-- Nomes próprios que a transcrição de áudio erra (filmes, séries, pessoas, marcas). Aprendido quando a pessoa confirma.
create table if not exists public.assessor_vocabulario (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  termo text not null,
  contexto text not null default '',
  created_at timestamptz not null default now(),
  unique (user_id, termo)
);
alter table public.assessor_vocabulario enable row level security;
drop policy if exists assessor_vocabulario_select on public.assessor_vocabulario;
create policy assessor_vocabulario_select on public.assessor_vocabulario for select using (user_id = auth.uid());
drop policy if exists assessor_vocabulario_delete on public.assessor_vocabulario;
create policy assessor_vocabulario_delete on public.assessor_vocabulario for delete using (user_id = auth.uid());

-- ══════════════════════════════════════════════════════════════
-- Assessor: e-mail (Gmail) — conexão OAuth, remetentes liberados e triagem (2026-10-09)
-- O refresh token do Google fica no Supabase Vault; as tabelas só guardam a referência.
-- ══════════════════════════════════════════════════════════════
create table if not exists public.assessor_email_estados (
  state text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  expira_em timestamptz not null default now() + interval '10 minutes'
);
alter table public.assessor_email_estados enable row level security;

create table if not exists public.assessor_email_contas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  provedor text not null default 'gmail',
  email text not null,
  segredo_id uuid,
  ativo boolean not null default true,
  conectado_em timestamptz not null default now(),
  ultima_varredura timestamptz,
  ultimo_erro text,
  unique (user_id, provedor)
);
alter table public.assessor_email_contas enable row level security;

create table if not exists public.assessor_email_remetentes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  padrao text not null,
  apelido text,
  vip boolean not null default false,
  created_at timestamptz not null default now(),
  unique (user_id, padrao)
);
alter table public.assessor_email_remetentes enable row level security;
create policy "remetentes: dono le" on public.assessor_email_remetentes for select using (user_id = auth.uid());
create policy "remetentes: dono cria" on public.assessor_email_remetentes for insert with check (user_id = auth.uid());
create policy "remetentes: dono altera" on public.assessor_email_remetentes for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "remetentes: dono exclui" on public.assessor_email_remetentes for delete using (user_id = auth.uid());

create table if not exists public.assessor_emails (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  conta_id uuid not null references public.assessor_email_contas(id) on delete cascade,
  mensagem_id text not null,
  remetente text,
  remetente_nome text,
  assunto text,
  recebido_em timestamptz,
  resumo text,
  categoria text,
  urgente boolean not null default false,
  vip boolean not null default false,
  sugestao jsonb,
  status text not null default 'novo',   -- novo | tarefa | compromisso | resolvido | ignorado
  alertado boolean not null default false,
  created_at timestamptz not null default now(),
  unique (conta_id, mensagem_id)
);
create index if not exists assessor_emails_user_recebido on public.assessor_emails (user_id, recebido_em desc);
alter table public.assessor_emails enable row level security;
create policy "emails: dono le" on public.assessor_emails for select using (user_id = auth.uid());
create policy "emails: dono altera" on public.assessor_emails for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "emails: dono exclui" on public.assessor_emails for delete using (user_id = auth.uid());
alter publication supabase_realtime add table public.assessor_emails;

alter table public.assessor_uso add column if not exists origem text default 'conversa';

-- RPCs do usuário
create or replace function public.assessor_email_iniciar(p_workspace_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_state text;
begin
  if v_uid is null then raise exception 'Não autenticado'; end if;
  if not exists (
    select 1 from workspaces w join workspace_membros m on m.workspace_id = w.id
    where w.id = p_workspace_id and w.perfil_tipo = 'pessoal' and m.user_id = v_uid and m.status = 'ativo'
  ) then raise exception 'O assessor só está disponível no seu perfil Pessoal'; end if;
  delete from assessor_email_estados where expira_em < now() or user_id = v_uid;
  v_state := encode(extensions.gen_random_bytes(24), 'hex');
  insert into assessor_email_estados (state, user_id, workspace_id) values (v_state, v_uid, p_workspace_id);
  return v_state;
end $$;

create or replace function public.assessor_email_status()
returns table (email text, provedor text, ativo boolean, conectado_em timestamptz, ultima_varredura timestamptz, ultimo_erro text)
language sql security definer set search_path = public as $$
  select email, provedor, ativo, conectado_em, ultima_varredura, ultimo_erro
  from assessor_email_contas where user_id = auth.uid();
$$;

create or replace function public.assessor_email_desconectar()
returns void language plpgsql security definer set search_path = public, vault as $$
declare r record;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  for r in select id, segredo_id from assessor_email_contas where user_id = auth.uid() loop
    if r.segredo_id is not null then delete from vault.secrets where id = r.segredo_id; end if;
    delete from assessor_email_contas where id = r.id;
  end loop;
end $$;

-- RPCs só do servidor (service_role)
create or replace function public.assessor_email_salvar_conta(p_state text, p_email text, p_refresh text)
returns uuid language plpgsql security definer set search_path = public, vault as $$
declare v_est record; v_conta record; v_segredo uuid; v_id uuid;
begin
  delete from assessor_email_estados where state = p_state and expira_em >= now()
    returning * into v_est;
  if v_est is null then raise exception 'Link de conexão expirado. Gere de novo no Taskfull.'; end if;
  select * into v_conta from assessor_email_contas where user_id = v_est.user_id and provedor = 'gmail';
  if v_conta.segredo_id is not null and p_refresh is not null then
    perform vault.update_secret(v_conta.segredo_id, p_refresh);
    v_segredo := v_conta.segredo_id;
  elsif p_refresh is not null then
    v_segredo := vault.create_secret(p_refresh, 'assessor_gmail_' || v_est.user_id::text);
  else
    v_segredo := v_conta.segredo_id;
  end if;
  if v_segredo is null then raise exception 'O Google não devolveu a autorização permanente. Tente conectar de novo.'; end if;
  insert into assessor_email_contas (user_id, workspace_id, provedor, email, segredo_id, ativo, conectado_em, ultimo_erro)
  values (v_est.user_id, v_est.workspace_id, 'gmail', p_email, v_segredo, true, now(), null)
  on conflict (user_id, provedor) do update set workspace_id = excluded.workspace_id, email = excluded.email,
    segredo_id = excluded.segredo_id, ativo = true, conectado_em = now(), ultimo_erro = null
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.assessor_email_contas_para_triagem()
returns table (id uuid, user_id uuid, workspace_id uuid, email text, refresh_token text, ultima_varredura timestamptz)
language sql security definer set search_path = public, vault as $$
  select c.id, c.user_id, c.workspace_id, c.email, s.decrypted_secret, c.ultima_varredura
  from assessor_email_contas c join vault.decrypted_secrets s on s.id = c.segredo_id
  where c.ativo;
$$;

revoke all on function public.assessor_email_salvar_conta(text, text, text) from public, anon, authenticated;
revoke all on function public.assessor_email_contas_para_triagem() from public, anon, authenticated;
grant execute on function public.assessor_email_salvar_conta(text, text, text) to service_role;
grant execute on function public.assessor_email_contas_para_triagem() to service_role;
revoke all on function public.assessor_email_iniciar(uuid) from public, anon;
revoke all on function public.assessor_email_status() from public, anon;
revoke all on function public.assessor_email_desconectar() from public, anon;
grant execute on function public.assessor_email_iniciar(uuid) to authenticated;
grant execute on function public.assessor_email_status() to authenticated;
grant execute on function public.assessor_email_desconectar() to authenticated;

-- Cron da triagem (rodar uma vez no SQL Editor, trocando <anon key>):
-- select cron.schedule('assessor-email-triagem', '*/15 * * * *', $c$ select net.http_post(
--   url := 'https://dubbmmjtbunzmdmfbbja.supabase.co/functions/v1/assessor-email-triagem',
--   headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer <anon key>'),
--   body := '{}'::jsonb, timeout_milliseconds := 120000); $c$);
