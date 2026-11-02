-- Full Control (módulo de casa inteligente do Task Full), 2026-11-02. Aditivo: tudo num schema novo "casa".
-- Nenhuma tabela existente é alterada neste arquivo.
create schema if not exists casa;
revoke all on schema casa from public, anon;
grant usage on schema casa to authenticated, service_role;

create table if not exists casa.casas (
  id uuid primary key default gen_random_uuid(),
  dono_id uuid not null references auth.users(id) on delete cascade,
  nome text not null default 'Minha casa',
  fuso text not null default 'America/Recife',
  latitude numeric, longitude numeric, raio_m integer,
  canal_token text not null default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  criado_em timestamptz not null default now()
);
create unique index if not exists casas_dono_nome on casa.casas (dono_id, nome);

create table if not exists casa.comodos (
  id uuid primary key default gen_random_uuid(),
  casa_id uuid not null references casa.casas(id) on delete cascade,
  nome text not null,
  externo boolean not null default false,
  apelidos text[] not null default '{}',
  ordem integer not null default 0
);
create index if not exists comodos_casa on casa.comodos (casa_id, ordem);

create table if not exists casa.dispositivos (
  id uuid primary key default gen_random_uuid(),
  casa_id uuid not null references casa.casas(id) on delete cascade,
  comodo_id uuid references casa.comodos(id) on delete set null,
  nome text not null,
  apelidos text[] not null default '{}',
  tipo text not null default 'outro' check (tipo in ('lampada','tv','tomada','ar_condicionado','sensor','outro')),
  protocolo text not null check (protocolo in ('android_tv','tuya','zigbee','lg_webos','smartthings','ir')),
  config jsonb not null default '{}'::jsonb,          -- ip, mac, broadcast, marca... SEM segredos
  capacidades text[] not null default '{}',
  estado jsonb not null default '{}'::jsonb,
  ultimo_contato timestamptz,
  ativo boolean not null default true
);
create index if not exists dispositivos_casa on casa.dispositivos (casa_id);

-- Segredos (certificado de pareamento etc.): sem política e sem acesso para o app; só funções do servidor da casa.
create table if not exists casa.dispositivo_credenciais (
  dispositivo_id uuid primary key references casa.dispositivos(id) on delete cascade,
  segredos jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

create table if not exists casa.grupos (
  id uuid primary key default gen_random_uuid(),
  casa_id uuid not null references casa.casas(id) on delete cascade,
  nome text not null,
  apelidos text[] not null default '{}'
);
create table if not exists casa.grupo_dispositivos (
  grupo_id uuid not null references casa.grupos(id) on delete cascade,
  dispositivo_id uuid not null references casa.dispositivos(id) on delete cascade,
  primary key (grupo_id, dispositivo_id)
);

create table if not exists casa.comandos (
  id uuid primary key default gen_random_uuid(),
  casa_id uuid not null references casa.casas(id) on delete cascade,
  criado_por uuid,
  origem text not null default 'app' check (origem in ('app','telegram','rotina','geofence','manual')),
  texto_original text,
  dispositivo_id uuid references casa.dispositivos(id) on delete cascade,
  grupo_id uuid references casa.grupos(id) on delete cascade,
  acao text not null check (acao in ('ligar','desligar','volume','mudo','descobrir','iniciar_pareamento','enviar_codigo')),
  parametros jsonb not null default '{}'::jsonb,
  status text not null default 'pendente' check (status in ('pendente','executando','ok','erro','expirado')),
  erro text,
  resultado jsonb,
  criado_em timestamptz not null default now(),
  executado_em timestamptz,
  expira_em timestamptz not null default now() + interval '2 minutes',
  check (dispositivo_id is not null or grupo_id is not null or acao = 'descobrir')
);
create index if not exists comandos_fila on casa.comandos (casa_id, status, criado_em);

create table if not exists casa.rotinas (
  id uuid primary key default gen_random_uuid(),
  casa_id uuid not null references casa.casas(id) on delete cascade,
  nome text not null,
  gatilho text not null check (gatilho in ('horario','por_do_sol','geofence_chegada','geofence_saida')),
  horario time, dias_semana smallint[] not null default '{0,1,2,3,4,5,6}',
  dispositivo_id uuid references casa.dispositivos(id) on delete cascade,
  grupo_id uuid references casa.grupos(id) on delete cascade,
  acao text not null check (acao in ('ligar','desligar','volume','mudo')),
  parametros jsonb not null default '{}'::jsonb,
  ativo boolean not null default true,
  ultima_execucao date
);

-- Chave do servidor da casa (só o hash fica no banco; revogável).
create table if not exists casa.executores (
  id uuid primary key default gen_random_uuid(),
  casa_id uuid not null references casa.casas(id) on delete cascade,
  nome text not null default 'Servidor da casa',
  chave_hash text not null,
  ativo boolean not null default true,
  ultimo_sinal timestamptz, versao text,
  criado_em timestamptz not null default now()
);
create index if not exists executores_hash on casa.executores (chave_hash);

-- Quem manda: dono da casa E recurso 'full_control' liberado (o master sempre passa em tem_recurso).
create or replace function casa.dono_da_casa(p_casa uuid) returns boolean
language sql stable security definer set search_path = casa, public, auth as $f$
  select auth.uid() is not null
     and exists (select 1 from casa.casas c where c.id = p_casa and c.dono_id = auth.uid())
     and public.tem_recurso(auth.uid(), 'full_control');
$f$;
grant execute on function casa.dono_da_casa(uuid) to authenticated;

alter table casa.casas enable row level security;
alter table casa.comodos enable row level security;
alter table casa.dispositivos enable row level security;
alter table casa.dispositivo_credenciais enable row level security;
alter table casa.grupos enable row level security;
alter table casa.grupo_dispositivos enable row level security;
alter table casa.comandos enable row level security;
alter table casa.rotinas enable row level security;
alter table casa.executores enable row level security;

revoke all on all tables in schema casa from anon, authenticated;
grant select on casa.casas to authenticated;
grant select, insert, update, delete on casa.comodos, casa.dispositivos, casa.grupos, casa.grupo_dispositivos, casa.rotinas to authenticated;
grant select, insert on casa.comandos to authenticated;

create policy casas_ver on casa.casas for select to authenticated using (casa.dono_da_casa(id));
create policy comodos_dono on casa.comodos for all to authenticated using (casa.dono_da_casa(casa_id)) with check (casa.dono_da_casa(casa_id));
create policy dispositivos_dono on casa.dispositivos for all to authenticated using (casa.dono_da_casa(casa_id)) with check (casa.dono_da_casa(casa_id));
create policy grupos_dono on casa.grupos for all to authenticated using (casa.dono_da_casa(casa_id)) with check (casa.dono_da_casa(casa_id));
create policy grupo_disp_dono on casa.grupo_dispositivos for all to authenticated
  using (exists (select 1 from casa.grupos g where g.id = grupo_id and casa.dono_da_casa(g.casa_id)))
  with check (exists (select 1 from casa.grupos g where g.id = grupo_id and casa.dono_da_casa(g.casa_id)));
create policy rotinas_dono on casa.rotinas for all to authenticated using (casa.dono_da_casa(casa_id)) with check (casa.dono_da_casa(casa_id));
create policy comandos_ver on casa.comandos for select to authenticated using (casa.dono_da_casa(casa_id));
-- O app só cria comando "pendente", dele mesmo, vencendo em até 5 min e sem resultado: quem muda o status é o servidor da casa.
create policy comandos_criar on casa.comandos for insert to authenticated with check (
  casa.dono_da_casa(casa_id) and status = 'pendente' and criado_por = auth.uid() and origem in ('app','manual')
  and erro is null and resultado is null and executado_em is null and expira_em <= now() + interval '5 minutes');
