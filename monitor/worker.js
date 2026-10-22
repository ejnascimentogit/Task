// Vigia externo do Taskfull e do e-commerce (Cloudflare Worker com Cron, a cada 5 min).
// Não depende do Supabase, do Docker nem do seu computador: se qualquer coisa cair, ele manda mensagem no Telegram (e, se configurado, no WhatsApp).
// Segredos (wrangler secret put ...): TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, SUPABASE_URL, SUPABASE_ANON_KEY
// Opcionais: CALLMEBOT_PHONE + CALLMEBOT_KEY (WhatsApp), EXTRA_CHECKS (JSON com as URLs do e-commerce, ver LEIA-ME.md), WUZAPI_URL.
// Estado (quantas falhas seguidas, quando avisou) fica no KV "ESTADO".

const ALERTAR_APOS = 2;        // falhas seguidas antes de avisar (evita alarme falso por um tropeço)
const LEMBRAR_A_CADA_MIN = 360; // enquanto continuar fora do ar, lembra a cada 6 h
const IDADE_MAX_VIGIA_MIN = 20; // o vigia do banco grava um sinal a cada 5 min; sem sinal há 20 min = automações paradas

async function pedir(url, opcoes = {}, ms = 12000) {
  const t0 = Date.now();
  try {
    const r = await fetch(url, { ...opcoes, signal: AbortSignal.timeout(ms) });
    const corpo = await r.text();
    return { ok: r.ok, status: r.status, corpo, ms: Date.now() - t0 };
  } catch (e) {
    return { ok: false, status: 0, corpo: '', ms: Date.now() - t0, erro: String(e && e.message || e).slice(0, 120) };
  }
}

// Cada verificação devolve { nome, ok, detalhe }.
export async function verificacoes(env, pedirFn = pedir) {
  const lista = [];
  const add = (nome, ok, detalhe) => lista.push({ nome, ok, detalhe });

  // 1) Site do Taskfull
  const site = await pedirFn('https://taskfull.ejnascimento1.workers.dev/');
  add('Taskfull (site)', site.ok && /taskfull/i.test(site.corpo), site.ok ? '' : (site.erro || 'HTTP ' + site.status));

  // 2) Banco e API do Supabase (o teste é o mesmo caminho que o app usa: PostgREST + chave + banco)
  if (env.SUPABASE_URL && env.SUPABASE_ANON_KEY) {
    const h = { apikey: env.SUPABASE_ANON_KEY, Authorization: 'Bearer ' + env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json' };
    const s = await pedirFn(env.SUPABASE_URL + '/rest/v1/rpc/saude_publica', { method: 'POST', headers: h, body: '{}' });
    let j = null; try { j = JSON.parse(s.corpo); } catch (_) { /* resposta que não é JSON */ }
    add('Supabase (API e banco)', s.ok && j && j.banco === true, s.ok ? '' : (s.erro || ('HTTP ' + s.status + ' ' + s.corpo.slice(0, 140))));
    if (j && j.banco === true) {
      const idade = j.vigia_idade_min;
      add('Automações (lembretes, WhatsApp programado)', idade !== null && idade !== undefined && idade <= IDADE_MAX_VIGIA_MIN,
        idade === null || idade === undefined ? 'sem sinal do vigia' : 'último sinal há ' + Math.round(idade) + ' min');
    }
    const a = await pedirFn(env.SUPABASE_URL + '/auth/v1/health', { headers: { apikey: env.SUPABASE_ANON_KEY } });
    add('Supabase (login)', a.ok, a.ok ? '' : (a.erro || 'HTTP ' + a.status));
  } else add('Supabase (configuração do vigia)', false, 'faltam SUPABASE_URL e SUPABASE_ANON_KEY');

  // 3) Servidor do WhatsApp (WuzAPI): só confere se responde
  if (env.WUZAPI_URL) {
    const w = await pedirFn(env.WUZAPI_URL.replace(/\/+$/, '') + '/');
    add('Servidor do WhatsApp (WuzAPI)', w.status > 0 && w.status < 500, w.status > 0 ? '' : (w.erro || 'sem resposta'));
  }

  // 4) E-commerce (e qualquer outra coisa): lista em JSON, ex.: [{"nome":"Loja","url":"https://loja.com","contem":"FullCommerce"}]
  let extras = [];
  try { extras = JSON.parse(env.EXTRA_CHECKS || '[]'); } catch (_) { add('Configuração EXTRA_CHECKS', false, 'JSON inválido'); }
  for (const c of extras) {
    const r = await pedirFn(c.url, { method: c.metodo || 'GET' });
    const okTexto = !c.contem || r.corpo.includes(c.contem);
    add(c.nome || c.url, r.ok && okTexto, r.ok ? (okTexto ? '' : 'a página abriu, mas não tem "' + c.contem + '"') : (r.erro || 'HTTP ' + r.status));
  }
  return lista;
}

// Decide o que mandar, dado o estado anterior. Devolve { estado, mensagens }.
export function decidir(lista, anterior, agora = Date.now()) {
  const novo = {}; const mensagens = [];
  for (const v of lista) {
    const a = anterior[v.nome] || { falhas: 0, avisadoEm: 0, desde: 0 };
    if (v.ok) {
      if (a.avisadoEm) mensagens.push(`✅ Voltou ao normal: ${v.nome}`);
      novo[v.nome] = { falhas: 0, avisadoEm: 0, desde: 0 };
    } else {
      const falhas = a.falhas + 1, desde = a.desde || agora;
      let avisadoEm = a.avisadoEm;
      if (!avisadoEm && falhas >= ALERTAR_APOS) { mensagens.push(`🚨 PROBLEMA: ${v.nome}${v.detalhe ? '\n' + v.detalhe : ''}`); avisadoEm = agora; }
      else if (avisadoEm && agora - avisadoEm >= LEMBRAR_A_CADA_MIN * 60000) {
        mensagens.push(`⚠️ Continua com problema (desde ${new Date(desde).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' })}): ${v.nome}${v.detalhe ? '\n' + v.detalhe : ''}`); avisadoEm = agora;
      }
      novo[v.nome] = { falhas, avisadoEm, desde };
    }
  }
  return { estado: novo, mensagens };
}

async function enviar(env, texto) {
  const res = [];
  if (env.TELEGRAM_BOT_TOKEN && env.TELEGRAM_CHAT_ID) {
    const r = await pedir(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ chat_id: env.TELEGRAM_CHAT_ID, text: texto }) });
    res.push('telegram:' + r.status);
  }
  if (env.CALLMEBOT_PHONE && env.CALLMEBOT_KEY) {   // WhatsApp no seu número, por um serviço gratuito de terceiros (ver LEIA-ME.md)
    const r = await pedir(`https://api.callmebot.com/whatsapp.php?phone=${encodeURIComponent(env.CALLMEBOT_PHONE)}&text=${encodeURIComponent(texto)}&apikey=${encodeURIComponent(env.CALLMEBOT_KEY)}`);
    res.push('whatsapp:' + r.status);
  }
  return res;
}

async function rodar(env) {
  const lista = await verificacoes(env);
  const anterior = JSON.parse((await env.ESTADO.get('estado')) || '{}');
  const { estado, mensagens } = decidir(lista, anterior);
  await env.ESTADO.put('estado', JSON.stringify(estado));
  await env.ESTADO.put('ultima_rodada', new Date().toISOString());
  let enviados = [];
  if (mensagens.length) enviados = await enviar(env, '🛰 Vigia Taskfull\n\n' + mensagens.join('\n\n'));
  return { verificacoes: lista, mensagens, enviados };
}

export default {
  async scheduled(_ev, env, ctx) { ctx.waitUntil(rodar(env)); },
  async fetch(req, env) {   // /teste manda uma mensagem de prova; /estado mostra o resultado sem avisar ninguém
    const u = new URL(req.url);
    if (u.pathname === '/teste' && u.searchParams.get('chave') === env.TELEGRAM_BOT_TOKEN?.slice(-8)) return Response.json({ enviados: await enviar(env, '✅ Teste do Vigia Taskfull: se você leu isto, o aviso funciona.') });
    if (u.pathname === '/estado') return Response.json({ verificacoes: await verificacoes(env), ultima_rodada: await env.ESTADO.get('ultima_rodada') });
    return new Response('Vigia Taskfull', { status: 200 });
  },
};
