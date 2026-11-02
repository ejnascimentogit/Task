// Chamadas ao Supabase. Só usa a chave pública (publishable) + a chave do servidor da casa (FC_CHAVE).
import { createClient } from '@supabase/supabase-js';

export function criarApi({ url, anonKey, chave, versao }) {
  const sb = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  async function rpc(nome, args) {
    const { data, error } = await sb.rpc(nome, { p_chave: chave, ...args });
    if (error) throw new Error(`${nome}: ${error.message}`);
    if (data && data.erro === 'chave') throw Object.assign(new Error('A chave do servidor da casa foi recusada (foi trocada ou revogada).'), { fatal: true });
    return data;
  }
  return {
    sb,
    sinal: () => rpc('casa_agente_sinal', { p_versao: versao }),
    pegar: (limite = 5) => rpc('casa_agente_pegar', { p_limite: limite }),
    resultado: (id, r) => rpc('casa_agente_resultado', { p_comando: id, p_ok: !!r.ok, p_erro: r.ok ? null : (r.erro || 'Falhou'), p_resultado: r.resultado || null }),
    estado: (dispositivo, estado, config) => rpc('casa_agente_estado', { p_dispositivo: dispositivo, p_estado: estado || null, p_config: config || null }),
    credencialLer: (dispositivo) => rpc('casa_agente_credencial_ler', { p_dispositivo: dispositivo }),
    credencialGravar: (dispositivo, segredos) => rpc('casa_agente_credencial_gravar', { p_dispositivo: dispositivo, p_segredos: segredos }),
    escutar(canal, aoAvisar, aoStatus) {
      const c = sb.channel(canal).on('broadcast', { event: 'novo' }, () => aoAvisar()).subscribe((status) => aoStatus && aoStatus(status));
      return () => sb.removeChannel(c);
    },
  };
}
