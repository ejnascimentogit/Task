-- Teste de saúde para o vigia externo (monitor/worker.js). Só devolve "o banco responde" e há quantos minutos o vigia interno
-- (cron whatsapp-vigia) gravou o último sinal. Nenhum dado de pessoa. Pode ser chamada com a chave anon.
create or replace function public.saude_publica() returns jsonb language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'banco', true,
    'vigia_idade_min', (select extract(epoch from (now() - max(verificado_em))) / 60 from public.whatsapp_saude_estado where chave = 'servidor')
  );
$$;
grant execute on function public.saude_publica() to anon, authenticated;
