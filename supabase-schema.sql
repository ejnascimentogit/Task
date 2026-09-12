-- Painel de Implantação — Intelipulse
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em "Run".

create table public.clientes (
  id uuid primary key default gen_random_uuid(),
  codigo text unique,
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
  updated_at timestamptz not null default now()
);

create table public.contatos_cliente (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id) on delete cascade,
  nome text not null,
  telefone text default '',
  cargo text default '',
  created_at timestamptz not null default now()
);

create table public.pendencias (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id) on delete cascade,
  texto text not null,
  responsavel text not null check (responsavel in ('cliente','rscrm')),
  feito boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.historico (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id) on delete cascade,
  data date not null default current_date,
  texto text not null,
  created_at timestamptz not null default now()
);

create table public.etapas (
  id text primary key,
  nome text not null,
  cor text not null default '#3B82F6',
  ordem int not null,
  created_at timestamptz not null default now()
);

create table public.pessoas (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  ordem int not null,
  user_id uuid unique references auth.users(id),
  apenas_visualizacao boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.tipos_agendamento (
  id text primary key,
  nome text not null,
  icone text not null default '📌',
  ordem int not null,
  created_at timestamptz not null default now()
);

insert into public.tipos_agendamento (id, nome, icone, ordem) values
  ('reuniao', 'Reunião', '🗓', 1),
  ('ligacao', 'Ligação', '📞', 2),
  ('mensagem', 'Mensagem', '💬', 3),
  ('email', 'E-mail', '✉️', 4),
  ('treinamento', 'Treinamento', '🎓', 5),
  ('outro', 'Outro', '📌', 6)
on conflict (id) do nothing;

create table public.agendamentos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid references public.clientes(id) on delete set null,
  titulo text not null,
  tipo text not null default 'reuniao',
  cliente_nome text default '',
  data date not null,
  hora time,
  observacao text default '',
  feito boolean not null default false,
  responsavel text default '',
  participantes text[] default '{}',
  reagendado_de date,
  created_at timestamptz not null default now()
);

create table public.atividades (
  id uuid primary key default gen_random_uuid(),
  responsavel text not null,
  criado_por text default '',
  titulo text not null,
  cliente_nome text default '',
  label text check (label in ('red','orange','yellow','blue') or label is null),
  coluna text not null default 'afazer' check (coluna in ('urgencias','afazer','andamento','concluida')),
  urgente boolean not null default false,
  cancelado boolean not null default false,
  resolucao text default '',
  participantes text[] default '{}',
  concluido_em date,
  ordem int not null default 0,
  created_at timestamptz not null default now()
);

create table public.atividade_imagens (
  id uuid primary key default gen_random_uuid(),
  atividade_id uuid not null references public.atividades(id) on delete cascade,
  path text not null,
  url text not null,
  created_at timestamptz not null default now()
);

create table public.treinamentos_etapas (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id) on delete cascade,
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
  id text primary key,
  nome text not null,
  ordem int not null,
  created_at timestamptz not null default now()
);

insert into public.treinamentos_padrao (id, nome, ordem) values
  ('levantamento_requisitos', 'Reunião de Levantamento de Requisitos', 1),
  ('configuracoes_parametrizacoes', 'Configurações e Parametrizações', 2),
  ('setup_integracao_erp', 'Setup de Integração ERP', 3),
  ('carga_dados', 'Carga de Dados', 4),
  ('setup_crm', 'Setup CRM', 5)
on conflict (id) do nothing;

create table public.treinamento_etapa_atividades (
  id uuid primary key default gen_random_uuid(),
  etapa_id uuid not null references public.treinamentos_etapas(id) on delete cascade,
  texto text not null,
  feito boolean not null default false,
  ordem int not null default 0,
  created_at timestamptz not null default now()
);

create index idx_trein_etapa_ativ_etapa on public.treinamento_etapa_atividades(etapa_id);
create index idx_treinamentos_etapas_cliente on public.treinamentos_etapas(cliente_id);
create index idx_atividade_imagens_atividade on public.atividade_imagens(atividade_id);
create index idx_contatos_cliente_cliente on public.contatos_cliente(cliente_id);
create index idx_pendencias_cliente on public.pendencias(cliente_id);
create index idx_historico_cliente on public.historico(cliente_id);
create index idx_agendamentos_cliente on public.agendamentos(cliente_id);
create index idx_agendamentos_data on public.agendamentos(data);
create index idx_atividades_responsavel on public.atividades(responsavel);
create index idx_atividades_concluido_em on public.atividades(concluido_em);

-- RLS: liberado para quem tiver a chave anon (ferramenta interna, sem login de usuário ainda)
alter table public.clientes enable row level security;
alter table public.contatos_cliente enable row level security;
alter table public.pendencias enable row level security;
alter table public.historico enable row level security;
alter table public.etapas enable row level security;
alter table public.pessoas enable row level security;
alter table public.tipos_agendamento enable row level security;
alter table public.agendamentos enable row level security;
alter table public.atividades enable row level security;
alter table public.atividade_imagens enable row level security;
alter table public.treinamentos_etapas enable row level security;
alter table public.treinamentos_padrao enable row level security;
alter table public.treinamento_etapa_atividades enable row level security;

create policy "allow all clientes" on public.clientes for all using (true) with check (true);
create policy "allow all contatos_cliente" on public.contatos_cliente for all using (true) with check (true);
create policy "allow all pendencias" on public.pendencias for all using (true) with check (true);
create policy "allow all historico" on public.historico for all using (true) with check (true);
create policy "allow all etapas" on public.etapas for all using (true) with check (true);
create policy "allow all pessoas" on public.pessoas for all using (true) with check (true);
create policy "allow all tipos_agendamento" on public.tipos_agendamento for all using (true) with check (true);
create policy "allow all agendamentos" on public.agendamentos for all using (true) with check (true);
create policy "allow all atividades" on public.atividades for all using (true) with check (true);
create policy "allow all atividade_imagens" on public.atividade_imagens for all using (true) with check (true);
create policy "allow all treinamentos_etapas" on public.treinamentos_etapas for all using (true) with check (true);
create policy "allow all treinamentos_padrao" on public.treinamentos_padrao for all using (true) with check (true);
create policy "allow all treinamento_etapa_atividades" on public.treinamento_etapa_atividades for all using (true) with check (true);

-- Storage: bucket público pra imagens anexadas às atividades (mesmo padrão de RLS permissiva do resto do painel)
insert into storage.buckets (id, name, public) values ('atividade-imagens', 'atividade-imagens', true)
on conflict (id) do nothing;

create policy "public select atividade-imagens" on storage.objects for select using (bucket_id = 'atividade-imagens');
create policy "public insert atividade-imagens" on storage.objects for insert with check (bucket_id = 'atividade-imagens');
create policy "public delete atividade-imagens" on storage.objects for delete using (bucket_id = 'atividade-imagens');

-- ══ Autenticação real (Fase 1) — liga cada login a uma pessoa da equipe ══
-- Só permite cadastro com e-mail @intelipulse.com.br (trava no banco, além da trava na tela)
create or replace function public.restrict_signup_domain()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.email !~* '@intelipulse\.com\.br$' then
    raise exception 'Cadastro permitido apenas para e-mails @intelipulse.com.br';
  end if;
  return new;
end;
$$;

drop trigger if exists restrict_signup_domain_trigger on auth.users;
create trigger restrict_signup_domain_trigger
before insert on auth.users
for each row execute function public.restrict_signup_domain();

-- Ao criar a conta, liga automaticamente ao registro já existente em "pessoas" (por nome,
-- sem diferenciar maiúsculas/minúsculas) — ou cria um novo se não achar nenhum
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  nome_meta text := coalesce(new.raw_user_meta_data->>'nome', split_part(new.email, '@', 1));
  existing_id uuid;
begin
  select id into existing_id from public.pessoas where lower(nome) = lower(nome_meta) and user_id is null limit 1;
  if existing_id is not null then
    update public.pessoas set user_id = new.id where id = existing_id;
  else
    insert into public.pessoas (nome, ordem, user_id)
    values (nome_meta, (select coalesce(max(ordem), 0) + 1 from public.pessoas), new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Função auxiliar: nome da pessoa logada — usada agora e reaproveitada na Fase 2 (RLS travado)
create or replace function public.current_pessoa_nome()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select nome from public.pessoas where user_id = auth.uid();
$$;
