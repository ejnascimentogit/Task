// Servidor da casa do Full Control. Abre conexão de SAÍDA com o Supabase (nenhuma porta é aberta no roteador).
import { criarApi } from './api.js';
import { criarTv } from './tv.js';
import { criarExecutor } from './executor.js';
import { rede } from './rede.js';
import { log } from './log.js';

const VERSAO = 'fc-executor 0.1.0';
const env = (k, padrao) => (process.env[k] && process.env[k].trim()) || padrao;
const URL_SB = env('SUPABASE_URL');
const ANON = env('SUPABASE_ANON_KEY');
const CHAVE = env('FC_CHAVE');
const SUBREDE = env('FC_SUBREDE', null);
const POLL_MS = Math.max(5000, Number(env('FC_POLL_MS', '15000')));
const SINAL_MS = 60000;

if (!URL_SB || !ANON || !CHAVE) {
  console.error('Faltam variáveis: SUPABASE_URL, SUPABASE_ANON_KEY e FC_CHAVE (veja .env.exemplo).');
  process.exit(1);
}

const api = criarApi({ url: URL_SB, anonKey: ANON, chave: CHAVE, versao: VERSAO });
const tv = criarTv();
let dispositivos = [];
const executor = criarExecutor({ api, tv, rede, subredeConfig: SUBREDE, log });

let acordado = false, acordarEspera = null, parar = false, canalAtual = null, desligarCanal = null;
const acordar = () => { acordado = true; if (acordarEspera) acordarEspera(); };
const esperarAte = (ms) => new Promise((res) => { const t = setTimeout(res, ms); acordarEspera = () => { clearTimeout(t); res(); }; });

async function sinal() {
  const info = await api.sinal();
  dispositivos = info.dispositivos || [];
  if (info.canal && info.canal !== canalAtual) {
    if (desligarCanal) desligarCanal();
    canalAtual = info.canal;
    desligarCanal = api.escutar(info.canal, acordar, (s) => log('info', 'canal de avisos: ' + s));
  }
  return info;
}

async function processarFila() {
  for (let guarda = 0; guarda < 20 && !parar; guarda++) {
    const cmds = await api.pegar(5);
    if (!Array.isArray(cmds) || !cmds.length) return;
    for (const cmd of cmds) {
      log('info', `executando ${cmd.acao}`, { id: cmd.id, origem: cmd.origem });
      const r = await executor.processar(cmd, dispositivos);
      await api.resultado(cmd.id, r);
      log(r.ok ? 'info' : 'aviso', `${cmd.acao}: ${r.ok ? 'ok' : r.erro}`, { id: cmd.id });
    }
  }
}

async function principal() {
  log('info', `${VERSAO} iniciando`);
  let ultimoSinal = 0, espera = 2000;
  while (!parar) {
    try {
      if (Date.now() - ultimoSinal > SINAL_MS) { await sinal(); ultimoSinal = Date.now(); log('info', `sinal enviado; ${dispositivos.length} dispositivo(s)`); }
      acordado = false;
      await processarFila();
      espera = 2000;
      if (!acordado) await esperarAte(POLL_MS);
    } catch (e) {
      if (e.fatal) { log('erro', e.message); process.exit(2); }
      log('erro', 'falha de comunicação, tentando de novo: ' + e.message);
      await esperarAte(espera);
      espera = Math.min(espera * 2, 30000);
    }
  }
}

for (const s of ['SIGINT', 'SIGTERM']) process.on(s, () => { parar = true; acordar(); log('info', 'encerrando'); setTimeout(() => process.exit(0), 500); });
principal();
