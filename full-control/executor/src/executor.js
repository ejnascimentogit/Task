// Regras do servidor da casa: recebe um comando do banco e faz acontecer na TV. Tudo por injeção de dependências
// (api, tv, rede), então os testes não precisam de TV, rede nem Supabase.
import { PORTA_COMANDO, PORTA_PAREAMENTO, subredeDeIp, broadcastDeIp, ipValido } from './rede.js';

const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
const MSG_NAO_ACHEI = 'Não encontrei a TV na rede. Ela pode estar desligada em espera profunda: na TV, deixe Energia > Modos de energia em "Consumo elevado".';

export function criarExecutor({ api, tv, rede, subredeConfig = null, esperar = pausa, log = () => {} }) {
  // TV está "no ar" se aceita conexão na porta de comando e, havendo identidade guardada, é a MESMA TV.
  async function ehATv(disp, ip) {
    if (!ip || !ipValido(ip)) return false;
    if (!(await rede.sondar(ip, PORTA_COMANDO))) return false;
    const guardada = disp.config && disp.config.identidade;
    if (!guardada) return true;
    const atual = await rede.identidade(ip);
    return !atual || atual === guardada;   // se não deu para ler, não condena
  }

  async function procurarNaRede(disp) {
    const base = (disp.config && disp.config.ultimo_ip) || null;
    const subrede = subredeConfig || subredeDeIp(base);
    if (!subrede) return null;
    const candidatos = await rede.varrer(subrede, { porta: PORTA_COMANDO });
    const guardada = disp.config && disp.config.identidade;
    if (guardada) {
      for (const ip of candidatos) if ((await rede.identidade(ip)) === guardada) return ip;
      return null;
    }
    return candidatos.length === 1 ? candidatos[0] : null;   // sem identidade guardada, só aceita se for a única
  }

  async function acordar(disp) {
    const c = disp.config || {};
    if (!c.mac) return false;
    const alvo = c.broadcast || broadcastDeIp(c.ultimo_ip);
    if (!alvo) return false;
    try { await rede.wol(c.mac, alvo, 5); } catch (e) { log('aviso', 'Wake-on-LAN falhou: ' + e.message); return false; }
    for (let i = 0; i < 15; i++) {   // até ~30 s esperando a porta abrir
      await esperar(2000);
      if (await ehATv(disp, c.ultimo_ip)) return true;
      const novo = await procurarNaRede(disp);
      if (novo) { disp.config = { ...c, ultimo_ip: novo }; return true; }
    }
    return false;
  }

  async function localizar(disp, { acordarSeNecessario }) {
    const c = disp.config || {};
    if (await ehATv(disp, c.ultimo_ip)) return c.ultimo_ip;
    const achado = await procurarNaRede(disp);
    if (achado) return achado;
    if (acordarSeNecessario && (await acordar(disp))) return (disp.config || {}).ultimo_ip;
    return null;
  }

  async function lembrar(disp, host, estado) {
    const config = { ultimo_ip: host };
    const id = await rede.identidade(host);
    if (id) config.identidade = id;
    await api.estado(disp.id, estado, config);
  }

  async function acionarTv(disp, cmd) {
    if (disp.protocolo !== 'android_tv') return { ok: false, erro: `"${disp.nome}": ainda não há driver para ${disp.protocolo}.` };
    const cred = await api.credencialLer(disp.id);
    if (!cred || !cred.cert || !cred.cert.key) return { ok: false, erro: `"${disp.nome}" ainda não foi pareada. Abra Full Control > Configuração e use "Parear a TV".` };
    const ligando = cmd.acao === 'ligar';
    let host = await localizar(disp, { acordarSeNecessario: ligando });
    if (!host) {
      if (cmd.acao === 'desligar') return { ok: false, erro: `"${disp.nome}": não encontrei a TV (desligada ou fora da rede).` };
      return { ok: false, erro: ligando ? MSG_NAO_ACHEI : `"${disp.nome}" parece desligada ou fora da rede.` };
    }
    let r = await tv.executar({ host, cert: cred.cert, acao: cmd.acao, parametros: cmd.parametros });
    if (!r.ok && r.codigo === 'sem_conexao' && ligando && !disp._acordada) {
      disp._acordada = true;
      if (await acordar(disp)) { host = (disp.config || {}).ultimo_ip || host; r = await tv.executar({ host, cert: cred.cert, acao: cmd.acao, parametros: cmd.parametros }); }
    }
    if (r.ok) { try { await lembrar(disp, host, { ligada: r.ligada }); } catch (e) { log('aviso', 'não consegui gravar o estado: ' + e.message); } }
    return r.ok ? { ok: true, ligada: r.ligada, ja: !!r.ja } : { ok: false, erro: r.erro || 'Falhou.' };
  }

  async function descobrir(dispositivos) {
    const conhecido = dispositivos.map((d) => (d.config || {}).ultimo_ip).find(Boolean);
    const subrede = subredeConfig || subredeDeIp(conhecido);
    if (!subrede) return { ok: false, erro: 'Não sei qual rede varrer. Defina FC_SUBREDE (ex.: 192.168.1.0/24) no servidor da casa.' };
    const ips = await rede.varrer(subrede, { porta: PORTA_COMANDO });
    const tvs = [];
    for (const ip of ips) {
      const id = await rede.identidade(ip);
      const conhecida = id ? dispositivos.find((d) => (d.config || {}).identidade === id) : null;
      tvs.push({ ip, identidade_curta: id ? id.replace(/:/g, '').slice(0, 12).toLowerCase() : null, cadastrada_como: conhecida ? conhecida.nome : null });
    }
    return { ok: true, resultado: { subrede, tvs } };
  }

  async function parear(disp) {
    if (disp.protocolo !== 'android_tv') return { ok: false, erro: 'Só TVs Android TV / Google TV podem ser pareadas aqui.' };
    const host = await localizar(disp, { acordarSeNecessario: false });
    if (!host) {
      // pareamento usa a porta 6467; tenta direto no último IP
      const ip = (disp.config || {}).ultimo_ip;
      if (!(ip && (await rede.sondar(ip, PORTA_PAREAMENTO)))) return { ok: false, erro: 'Não encontrei a TV na rede. Ligue a TV (tela acesa) e tente de novo.' };
      const r = await tv.iniciarPareamento(disp.id, ip);
      return r.ok ? { ok: true, resultado: { aguardando_codigo: true } } : { ok: false, erro: r.erro };
    }
    const r = await tv.iniciarPareamento(disp.id, host);
    if (r.ok) await lembrar(disp, host, null).catch(() => {});
    return r.ok ? { ok: true, resultado: { aguardando_codigo: true } } : { ok: false, erro: r.erro };
  }

  async function concluirPareamento(disp, codigo) {
    const r = await tv.enviarCodigo(disp.id, codigo);
    if (!r.ok) return { ok: false, erro: r.erro };
    await api.credencialGravar(disp.id, { cert: r.certificado });
    return { ok: true, resultado: { pareada: true } };
  }

  // Executa um comando devolvido por casa_agente_pegar e devolve { ok, erro?, resultado? } (a gravação fica com quem chama).
  async function processar(cmd, dispositivosConhecidos = []) {
    try {
      if (cmd.acao === 'descobrir') return await descobrir(dispositivosConhecidos);
      const alvos = cmd.dispositivos || [];
      if (!alvos.length) return { ok: false, erro: 'Esse comando não tem nenhum dispositivo.' };
      if (cmd.acao === 'iniciar_pareamento') return await parear(alvos[0]);
      if (cmd.acao === 'enviar_codigo') return await concluirPareamento(alvos[0], cmd.parametros && cmd.parametros.codigo);
      if (!['ligar', 'desligar', 'volume', 'mudo'].includes(cmd.acao)) return { ok: false, erro: 'Ação não suportada: ' + cmd.acao };
      const resultados = [];
      for (const d of alvos) resultados.push({ nome: d.nome, ...(await acionarTv(d, cmd)) });
      const falhas = resultados.filter((x) => !x.ok);
      if (!falhas.length) return { ok: true, resultado: { dispositivos: resultados.map((x) => ({ nome: x.nome, ligada: x.ligada, ja: x.ja })) } };
      return { ok: false, erro: falhas.map((x) => x.erro).join(' | ').slice(0, 280) };
    } catch (e) {
      log('erro', 'exceção ao processar comando', { acao: cmd.acao, msg: e.message });
      return { ok: false, erro: 'Erro inesperado no servidor da casa.' };
    }
  }

  return { processar, localizar, procurarNaRede };
}
