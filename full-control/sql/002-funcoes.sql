-- Full Control: funções (frase de voz -> comando, comandos do app, funções do servidor da casa), aviso por Realtime e vencimento.
create or replace function casa.norm(t text) returns text language sql immutable as $f$
  select btrim(regexp_replace(regexp_replace(translate(lower(coalesce(t,'')), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'));
$f$;

-- Núcleo (não exposto): texto -> comando. Ação por palavras; alvo = apelido mais longo contido na frase (dispositivo antes de grupo).
create or replace function casa._frase_para_comando(p_casa uuid, p_texto text, p_origem text, p_user uuid) returns uuid
language plpgsql security definer set search_path = casa, public as $f$
declare
  t text := ' ' || casa.norm(p_texto) || ' ';
  v_acao text; v_params jsonb := '{}'::jsonb; v_dir text; v_passos int := 3;
  v_disp uuid; v_grupo uuid; v_caps text[]; v_melhor int := 0; r record; ap text; v_id uuid; p text[];
begin
  if length(t) <= 2 then raise exception 'Não entendi a ação'; end if;
  if t ~ ' (desliga|desligar|desligue|apaga|apagar|apague) ' then v_acao := 'desligar';
  elsif t ~ ' (liga|ligar|ligue|acende|acender|acenda|ativa|ativar|ative) ' then v_acao := 'ligar';
  elsif t ~ ' (mudo|silencio|silenciar|silencia) ' or t ~ ' (tira|corta|cortar) o som ' then v_acao := 'mudo';
  elsif t ~ ' (abaixa|abaixar|abaixe|diminui|diminuir|diminua|baixa|baixar|baixe|reduz|reduzir|reduza) ' and t ~ ' (volume|som) ' then v_acao := 'volume'; v_dir := 'menos';
  elsif t ~ ' (aumenta|aumentar|aumente|sobe|subir|suba|levanta|levantar|eleva|elevar) ' and t ~ ' (volume|som) ' then v_acao := 'volume'; v_dir := 'mais';
  else raise exception 'Não entendi a ação'; end if;

  if v_acao = 'volume' then
    if t ~ ' [0-9]{1,2} ' then v_passos := (substring(t from ' ([0-9]{1,2}) '))::int;
    else
      foreach p slice 1 in array array[array['um','1'],array['uma','1'],array['dois','2'],array['duas','2'],array['tres','3'],array['quatro','4'],array['cinco','5'],array['seis','6'],array['sete','7'],array['oito','8'],array['nove','9'],array['dez','10']] loop
        if position(' ' || p[1] || ' ' in t) > 0 then v_passos := p[2]::int; exit; end if;
      end loop;
    end if;
    v_params := jsonb_build_object('direcao', v_dir, 'passos', least(20, greatest(1, v_passos)));
  end if;

  for r in select d.id, d.nome, d.apelidos, d.capacidades from casa.dispositivos d where d.casa_id = p_casa and d.ativo loop
    foreach ap in array (array[r.nome] || r.apelidos) loop
      ap := casa.norm(ap);
      if ap <> '' and position(' ' || ap || ' ' in t) > 0 and length(ap) > v_melhor then v_melhor := length(ap); v_disp := r.id; v_caps := r.capacidades; end if;
    end loop;
  end loop;
  if v_disp is null then
    for r in select g.id, g.nome, g.apelidos from casa.grupos g where g.casa_id = p_casa loop
      foreach ap in array (array[r.nome] || r.apelidos) loop
        ap := casa.norm(ap);
        if ap <> '' and position(' ' || ap || ' ' in t) > 0 and length(ap) > v_melhor then v_melhor := length(ap); v_grupo := r.id; end if;
      end loop;
    end loop;
  end if;
  -- "abaixa o volume" / "mudo" sem dizer qual: se só um aparelho da casa aceita a ação, é ele.
  if v_disp is null and v_grupo is null and v_acao in ('volume','mudo') then
    select d.id, d.capacidades into v_disp, v_caps from casa.dispositivos d
     where d.casa_id = p_casa and d.ativo and v_acao = any (d.capacidades) and (select count(*) from casa.dispositivos d2 where d2.casa_id = p_casa and d2.ativo and v_acao = any (d2.capacidades)) = 1;
  end if;
  if v_disp is null and v_grupo is null then raise exception 'Não entendi qual dispositivo'; end if;
  if v_grupo is not null and v_acao in ('volume','mudo') then raise exception 'Essa ação não funciona em um grupo de dispositivos'; end if;
  if v_disp is not null and coalesce(array_length(v_caps,1),0) > 0 and not (v_acao = any (v_caps)) then raise exception 'Esse dispositivo não aceita essa ação'; end if;

  insert into casa.comandos (casa_id, criado_por, origem, texto_original, dispositivo_id, grupo_id, acao, parametros)
  values (p_casa, p_user, p_origem, left(p_texto, 300), v_disp, v_grupo, v_acao, v_params) returning id into v_id;
  return v_id;
end $f$;

-- Chamada pelo app (voz ou texto): casa.executar_frase(texto, origem) -> id do comando.
create or replace function casa.executar_frase(p_texto text, p_origem text default 'app') returns uuid
language plpgsql security definer set search_path = casa, public as $f$
declare v_casa uuid;
begin
  if auth.uid() is null then raise exception 'Faça login para usar o Full Control'; end if;
  if p_origem not in ('app','manual') then raise exception 'Origem inválida'; end if;
  select c.id into v_casa from casa.casas c where c.dono_id = auth.uid() order by c.criado_em limit 1;
  if v_casa is null or not public.tem_recurso(auth.uid(), 'full_control') then raise exception 'O Full Control não está liberado para a sua conta'; end if;
  return casa._frase_para_comando(v_casa, p_texto, p_origem, auth.uid());
end $f$;

-- Botões que já sabem o alvo.
create or replace function casa.enviar_comando(p_dispositivo uuid, p_acao text, p_parametros jsonb default '{}'::jsonb) returns uuid
language plpgsql security definer set search_path = casa, public as $f$
declare v_casa uuid; v_id uuid; v_params jsonb := '{}'::jsonb; v_dir text; v_passos int; v_cod text;
begin
  if auth.uid() is null then raise exception 'Faça login para usar o Full Control'; end if;
  if p_acao not in ('ligar','desligar','volume','mudo','descobrir','iniciar_pareamento','enviar_codigo') then raise exception 'Ação inválida'; end if;
  if p_dispositivo is null then
    if p_acao <> 'descobrir' then raise exception 'Escolha o dispositivo'; end if;
    select c.id into v_casa from casa.casas c where c.dono_id = auth.uid() order by c.criado_em limit 1;
  else
    select d.casa_id into v_casa from casa.dispositivos d where d.id = p_dispositivo;
  end if;
  if v_casa is null or not casa.dono_da_casa(v_casa) then raise exception 'Sem permissão para este dispositivo'; end if;
  if p_acao = 'volume' then
    v_dir := p_parametros->>'direcao';
    if v_dir not in ('mais','menos') then raise exception 'Direção do volume inválida'; end if;
    v_passos := least(20, greatest(1, coalesce((p_parametros->>'passos')::int, 1)));
    v_params := jsonb_build_object('direcao', v_dir, 'passos', v_passos);
  elsif p_acao = 'enviar_codigo' then
    v_cod := p_parametros->>'codigo';
    if v_cod is null or v_cod !~ '^[A-Za-z0-9]{6}$' then raise exception 'O código tem 6 letras ou números'; end if;
    v_params := jsonb_build_object('codigo', upper(v_cod));
  end if;
  insert into casa.comandos (casa_id, criado_por, origem, dispositivo_id, acao, parametros)
  values (v_casa, auth.uid(), 'app', p_dispositivo, p_acao, v_params) returning id into v_id;
  return v_id;
end $f$;

create or replace function casa.minha_casa() returns jsonb
language plpgsql stable security definer set search_path = casa, public as $f$
declare v jsonb;
begin
  if auth.uid() is null or not public.tem_recurso(auth.uid(), 'full_control') then return null; end if;
  select jsonb_build_object(
    'casa', jsonb_build_object('id', c.id, 'nome', c.nome, 'fuso', c.fuso),
    'comodos', coalesce((select jsonb_agg(to_jsonb(m) order by m.ordem, m.nome) from casa.comodos m where m.casa_id = c.id), '[]'::jsonb),
    'dispositivos', coalesce((select jsonb_agg(to_jsonb(d) order by d.nome) from casa.dispositivos d where d.casa_id = c.id), '[]'::jsonb),
    'grupos', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'nome', g.nome, 'apelidos', g.apelidos,
        'dispositivos', coalesce((select jsonb_agg(gd.dispositivo_id) from casa.grupo_dispositivos gd where gd.grupo_id = g.id), '[]'::jsonb)) order by g.nome)
        from casa.grupos g where g.casa_id = c.id), '[]'::jsonb),
    'servidor', jsonb_build_object(
      'ultimo_sinal', (select max(e.ultimo_sinal) from casa.executores e where e.casa_id = c.id and e.ativo),
      'tem_chave', exists (select 1 from casa.executores e where e.casa_id = c.id and e.ativo)))
  into v from casa.casas c where c.dono_id = auth.uid() order by c.criado_em limit 1;
  return v;
end $f$;

create or replace function casa.status_comando(p_id uuid) returns jsonb
language sql stable security definer set search_path = casa, public as $f$
  select jsonb_build_object('status', c.status, 'erro', c.erro, 'resultado', c.resultado)
  from casa.comandos c where c.id = p_id and casa.dono_da_casa(c.casa_id);
$f$;

-- Chave do servidor da casa: aparece uma vez; no banco fica só o hash. Gerar outra desativa a anterior.
create or replace function casa.gerar_chave_executor() returns text
language plpgsql security definer set search_path = casa, public as $f$
declare v_casa uuid; v_chave text;
begin
  if auth.uid() is null then raise exception 'Faça login'; end if;
  select c.id into v_casa from casa.casas c where c.dono_id = auth.uid() order by c.criado_em limit 1;
  if v_casa is null or not casa.dono_da_casa(v_casa) then raise exception 'Sem permissão'; end if;
  v_chave := 'fc_' || replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  update casa.executores set ativo = false where casa_id = v_casa and ativo;
  insert into casa.executores (casa_id, chave_hash) values (v_casa, encode(sha256(convert_to(v_chave, 'UTF8')), 'hex'));
  return v_chave;
end $f$;

-- Quando o master tira o acesso, comandos que ainda não rodaram são cancelados.
create or replace function casa.cancelar_pendentes(p_user uuid) returns void
language sql security definer set search_path = casa, public as $f$
  update casa.comandos set status = 'expirado', erro = 'Acesso ao Full Control removido', executado_em = now()
  where status = 'pendente' and casa_id in (select id from casa.casas where dono_id = p_user);
$f$;

-- ───── Funções do servidor da casa (chamadas com a chave do executor; sem login de usuário) ─────
create or replace function casa._executor(p_chave text) returns casa.executores
language sql stable security definer set search_path = casa, public as $f$
  select e.* from casa.executores e where e.ativo and e.chave_hash = encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex') limit 1;
$f$;

create or replace function casa._disp_json(p_id uuid) returns jsonb
language sql stable security definer set search_path = casa, public as $f$
  select jsonb_build_object('id', d.id, 'nome', d.nome, 'tipo', d.tipo, 'protocolo', d.protocolo, 'config', d.config, 'ativo', d.ativo) from casa.dispositivos d where d.id = p_id;
$f$;

create or replace function casa.agente_sinal(p_chave text, p_versao text default null) returns jsonb
language plpgsql security definer set search_path = casa, public as $f$
declare v_ex casa.executores; v_tok text;
begin
  v_ex := casa._executor(p_chave);
  if v_ex.id is null then return jsonb_build_object('erro', 'chave'); end if;
  update casa.executores set ultimo_sinal = now(), versao = left(p_versao, 40) where id = v_ex.id;
  update casa.comandos set status = 'expirado', erro = 'Venceu sem o servidor da casa executar', executado_em = now()
   where casa_id = v_ex.casa_id and status = 'pendente' and expira_em < now();
  select canal_token into v_tok from casa.casas where id = v_ex.casa_id;
  return jsonb_build_object('ok', true, 'casa_id', v_ex.casa_id, 'canal', 'casa:' || v_tok,
    'dispositivos', coalesce((select jsonb_agg(casa._disp_json(d.id)) from casa.dispositivos d where d.casa_id = v_ex.casa_id), '[]'::jsonb));
end $f$;

-- Pega os comandos pendentes (e só os que ainda valem) trocando 'pendente' -> 'executando' de uma vez: executa uma vez só.
create or replace function casa.agente_pegar(p_chave text, p_limite int default 5) returns jsonb
language plpgsql security definer set search_path = casa, public as $f$
declare v_ex casa.executores; v_out jsonb;
begin
  v_ex := casa._executor(p_chave);
  if v_ex.id is null then return jsonb_build_object('erro', 'chave'); end if;
  with pegos as (
    update casa.comandos c set status = 'executando'
     where c.id in (select x.id from casa.comandos x where x.casa_id = v_ex.casa_id and x.status = 'pendente' and x.expira_em > now()
                    order by x.criado_em limit greatest(1, least(coalesce(p_limite, 5), 20)) for update skip locked)
    returning c.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'acao', p.acao, 'parametros', p.parametros, 'origem', p.origem,
      'dispositivos', case
        when p.dispositivo_id is not null then jsonb_build_array(casa._disp_json(p.dispositivo_id))
        when p.grupo_id is not null then coalesce((select jsonb_agg(casa._disp_json(gd.dispositivo_id)) from casa.grupo_dispositivos gd join casa.dispositivos d on d.id = gd.dispositivo_id where gd.grupo_id = p.grupo_id and d.ativo), '[]'::jsonb)
        else '[]'::jsonb end) order by p.criado_em), '[]'::jsonb)
  into v_out from pegos p;
  return v_out;
end $f$;

create or replace function casa.agente_resultado(p_chave text, p_comando uuid, p_ok boolean, p_erro text default null, p_resultado jsonb default null) returns jsonb
language plpgsql security definer set search_path = casa, public as $f$
declare v_ex casa.executores; v_n int;
begin
  v_ex := casa._executor(p_chave);
  if v_ex.id is null then return jsonb_build_object('erro', 'chave'); end if;
  update casa.comandos set status = case when p_ok then 'ok' else 'erro' end,
         erro = case when p_ok then null else left(coalesce(p_erro, 'Falhou'), 300) end,
         resultado = p_resultado, executado_em = now(),
         parametros = case when acao = 'enviar_codigo' then '{}'::jsonb else parametros end
   where id = p_comando and casa_id = v_ex.casa_id and status = 'executando';
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', v_n = 1);
end $f$;

-- Estado do aparelho e dados de rede que o servidor descobriu (só chaves permitidas; nada de segredo).
create or replace function casa.agente_estado(p_chave text, p_dispositivo uuid, p_estado jsonb default null, p_config jsonb default null) returns jsonb
language plpgsql security definer set search_path = casa, public as $f$
declare v_ex casa.executores; v_n int;
begin
  v_ex := casa._executor(p_chave);
  if v_ex.id is null then return jsonb_build_object('erro', 'chave'); end if;
  update casa.dispositivos d set estado = coalesce(p_estado, d.estado), ultimo_contato = now(),
         config = d.config || coalesce((select jsonb_object_agg(k, v) from jsonb_each(coalesce(p_config, '{}'::jsonb)) as t(k, v) where k in ('ultimo_ip', 'identidade', 'nome_tv')), '{}'::jsonb)
   where d.id = p_dispositivo and d.casa_id = v_ex.casa_id;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', v_n = 1);
end $f$;

create or replace function casa.agente_credencial_ler(p_chave text, p_dispositivo uuid) returns jsonb
language plpgsql security definer set search_path = casa, public as $f$
declare v_ex casa.executores; v jsonb;
begin
  v_ex := casa._executor(p_chave);
  if v_ex.id is null then return jsonb_build_object('erro', 'chave'); end if;
  select c.segredos into v from casa.dispositivo_credenciais c join casa.dispositivos d on d.id = c.dispositivo_id
   where c.dispositivo_id = p_dispositivo and d.casa_id = v_ex.casa_id;
  return coalesce(v, '{}'::jsonb);
end $f$;

create or replace function casa.agente_credencial_gravar(p_chave text, p_dispositivo uuid, p_segredos jsonb) returns jsonb
language plpgsql security definer set search_path = casa, public as $f$
declare v_ex casa.executores;
begin
  v_ex := casa._executor(p_chave);
  if v_ex.id is null then return jsonb_build_object('erro', 'chave'); end if;
  if not exists (select 1 from casa.dispositivos d where d.id = p_dispositivo and d.casa_id = v_ex.casa_id) then return jsonb_build_object('erro', 'dispositivo'); end if;
  insert into casa.dispositivo_credenciais (dispositivo_id, segredos, atualizado_em) values (p_dispositivo, coalesce(p_segredos, '{}'::jsonb), now())
  on conflict (dispositivo_id) do update set segredos = excluded.segredos, atualizado_em = now();
  return jsonb_build_object('ok', true);
end $f$;

-- Aviso por Realtime ("tem comando novo") em canal com nome secreto; sem dados. Se falhar, a checagem de reserva do servidor pega.
create or replace function casa.avisar_comando() returns trigger
language plpgsql security definer set search_path = casa, public, realtime as $f$
declare v_tok text;
begin
  select canal_token into v_tok from casa.casas where id = new.casa_id;
  perform realtime.send(jsonb_build_object('id', new.id), 'novo', 'casa:' || v_tok, false);
  return new;
exception when others then
  return new;
end $f$;
do $b$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_casa_avisar_comando') then
    create trigger trg_casa_avisar_comando after insert on casa.comandos for each row execute function casa.avisar_comando();
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'casa' and tablename = 'comandos') then
    alter publication supabase_realtime add table casa.comandos;
  end if;
end $b$;

-- Vence o que ficou parado (a cada minuto).
select cron.schedule('casa-expirar-comandos', '* * * * *', $c$
  update casa.comandos set status = 'expirado', erro = 'Venceu sem o servidor da casa executar', executado_em = now() where status = 'pendente' and expira_em < now();
  update casa.comandos set status = 'erro', erro = 'O servidor da casa não terminou a tempo', executado_em = now() where status = 'executando' and criado_em < now() - interval '3 minutes';
$c$);

-- ───── Funções públicas (o schema casa não é exposto na API; o app e o servidor chamam estas; todas SECURITY DEFINER e conferem o dono/chave por dentro) ─────
create or replace function public.casa_executar_frase(p_texto text, p_origem text default 'app') returns uuid language sql security definer set search_path = public, casa as $f$ select casa.executar_frase(p_texto, p_origem) $f$;
create or replace function public.casa_enviar_comando(p_dispositivo uuid, p_acao text, p_parametros jsonb default '{}'::jsonb) returns uuid language sql security definer set search_path = public, casa as $f$ select casa.enviar_comando(p_dispositivo, p_acao, p_parametros) $f$;
create or replace function public.casa_minha_casa() returns jsonb language sql stable security definer set search_path = public, casa as $f$ select casa.minha_casa() $f$;
create or replace function public.casa_status_comando(p_id uuid) returns jsonb language sql stable security definer set search_path = public, casa as $f$ select casa.status_comando(p_id) $f$;
create or replace function public.casa_gerar_chave_executor() returns text language sql security definer set search_path = public, casa as $f$ select casa.gerar_chave_executor() $f$;
create or replace function public.casa_agente_sinal(p_chave text, p_versao text default null) returns jsonb language sql security definer set search_path = public, casa as $f$ select casa.agente_sinal(p_chave, p_versao) $f$;
create or replace function public.casa_agente_pegar(p_chave text, p_limite int default 5) returns jsonb language sql security definer set search_path = public, casa as $f$ select casa.agente_pegar(p_chave, p_limite) $f$;
create or replace function public.casa_agente_resultado(p_chave text, p_comando uuid, p_ok boolean, p_erro text default null, p_resultado jsonb default null) returns jsonb language sql security definer set search_path = public, casa as $f$ select casa.agente_resultado(p_chave, p_comando, p_ok, p_erro, p_resultado) $f$;
create or replace function public.casa_agente_estado(p_chave text, p_dispositivo uuid, p_estado jsonb default null, p_config jsonb default null) returns jsonb language sql security definer set search_path = public, casa as $f$ select casa.agente_estado(p_chave, p_dispositivo, p_estado, p_config) $f$;
create or replace function public.casa_agente_credencial_ler(p_chave text, p_dispositivo uuid) returns jsonb language sql security definer set search_path = public, casa as $f$ select casa.agente_credencial_ler(p_chave, p_dispositivo) $f$;
create or replace function public.casa_agente_credencial_gravar(p_chave text, p_dispositivo uuid, p_segredos jsonb) returns jsonb language sql security definer set search_path = public, casa as $f$ select casa.agente_credencial_gravar(p_chave, p_dispositivo, p_segredos) $f$;

-- Quem pode chamar o quê.
revoke all on all functions in schema casa from public, anon, authenticated;
grant execute on function casa.dono_da_casa(uuid) to authenticated;
grant execute on function casa.executar_frase(text, text), casa.enviar_comando(uuid, text, jsonb), casa.minha_casa(), casa.status_comando(uuid), casa.gerar_chave_executor() to authenticated;
-- casa.agente_* ficam só para o dono do banco: o servidor da casa entra pelas funções public.casa_agente_* abaixo.
revoke all on function public.casa_executar_frase(text, text), public.casa_enviar_comando(uuid, text, jsonb), public.casa_minha_casa(), public.casa_status_comando(uuid), public.casa_gerar_chave_executor(),
  public.casa_agente_sinal(text, text), public.casa_agente_pegar(text, int), public.casa_agente_resultado(text, uuid, boolean, text, jsonb), public.casa_agente_estado(text, uuid, jsonb, jsonb),
  public.casa_agente_credencial_ler(text, uuid), public.casa_agente_credencial_gravar(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.casa_executar_frase(text, text), public.casa_enviar_comando(uuid, text, jsonb), public.casa_minha_casa(), public.casa_status_comando(uuid), public.casa_gerar_chave_executor() to authenticated;
grant execute on function public.casa_agente_sinal(text, text), public.casa_agente_pegar(text, int), public.casa_agente_resultado(text, uuid, boolean, text, jsonb), public.casa_agente_estado(text, uuid, jsonb, jsonb),
  public.casa_agente_credencial_ler(text, uuid), public.casa_agente_credencial_gravar(text, uuid, jsonb) to anon, authenticated;
