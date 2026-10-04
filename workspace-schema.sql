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
