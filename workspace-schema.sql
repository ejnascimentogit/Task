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
