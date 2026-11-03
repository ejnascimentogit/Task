// Parte Node do aplicativo Full Control (roda DENTRO do celular, via plugin Capawesome/nodejs-mobile, Node 18).
// Fala direto com a TV (Android TV Remote v2: pareamento na porta 6467, comandos na 6466) pela rede Wi-Fi.
'use strict';
const { app, channel } = require('bridge');
const fs = require('fs');
const path = require('path');
const net = require('net');
const Module = require('module');

const post = (evento, dados) => { try { channel.post(evento, dados === undefined ? null : dados); } catch (_) { /* ponte indisponível */ } };
const log = (nivel, msg) => post('log', { nivel, msg: String(msg).slice(0, 500), t: new Date().toISOString().slice(11, 19) });

// A biblioteca deixa promessas soltas ao perder a conexão; no Node 18 isso derrubaria o processo (e ele não reinicia no app).
process.on('unhandledRejection', (e) => log('aviso', 'promessa rejeitada: ' + ((e && e.message) || e)));
process.on('uncaughtException', (e) => { log('erro', 'exceção: ' + ((e && e.message) || e)); post('tv:resultado', { ok: false, erro: 'Erro interno: ' + ((e && e.message) || e) }); });

// A biblioteca consulta o sistema (systeminformation) só para escrever o nome do aparelho; no Android isso pode falhar. Troca por valor fixo.
const carregarOriginal = Module._load;
Module._load = function (request) {
  if (request === 'systeminformation') return { system: async () => ({ manufacturer: 'Full Control', model: 'Android' }) };
  return carregarOriginal.apply(this, arguments);
};
const { AndroidRemote, RemoteKeyCode, RemoteDirection } = require('androidtv-remote');

const arquivoCert = () => path.join(app.datadir(), 'cert.json');
function lerCert() { try { const c = JSON.parse(fs.readFileSync(arquivoCert(), 'utf8')); return c && c.key && c.cert ? c : null; } catch (_) { return null; } }

// O stop() da biblioteca derruba a conexão, mas ela mesma reconecta 1 s depois, para sempre. Aqui anulamos a reconexão.
function pararDeVez(remote) {
  const neutralizar = (m) => { if (m) m.start = async () => false; };
  let rm = remote.remoteManager;
  neutralizar(rm);
  try { Object.defineProperty(remote, 'remoteManager', { configurable: true, get: () => rm, set: (v) => { rm = v; neutralizar(v); } }); } catch (_) { /* já definido */ }
  try { if (rm) rm.stop(); } catch (_) { /* já parado */ }
}

function sondar(host, porta, ms = 2000) {
  return new Promise((resolve) => {
    const s = net.connect({ host, port: porta });
    const fim = (ok) => { s.destroy(); resolve(ok); };
    s.setTimeout(ms, () => fim(false));
    s.once('connect', () => fim(true));
    s.once('error', () => fim(false));
  });
}

let sessaoPareamento = null;
function encerrarPareamento() { if (sessaoPareamento) { clearTimeout(sessaoPareamento.timer); pararDeVez(sessaoPareamento.remote); sessaoPareamento = null; } }

function parear(host) {
  encerrarPareamento();
  log('info', `Pareando com ${host} (certificado novo: no celular pode levar até 1 minuto)...`);
  const remote = new AndroidRemote(host, { service_name: 'Full Control', pairing_port: 6467, remote_port: 6466 });
  sessaoPareamento = { remote, timer: setTimeout(() => { log('aviso', 'Pareamento expirou (3 min sem concluir).'); post('tv:pareamento', { ok: false, erro: 'O pareamento expirou. Tente de novo.' }); encerrarPareamento(); }, 180000) };
  remote.on('secret', () => { log('info', 'A TV mostrou o código. Digite os 6 caracteres.'); post('tv:codigo-pedido'); });
  remote.on('ready', () => {
    try { fs.writeFileSync(arquivoCert(), JSON.stringify(remote.getCertificate())); } catch (e) { log('erro', 'não consegui guardar o certificado: ' + e.message); }
    log('info', 'Pareado! Certificado guardado no aparelho.');
    post('tv:pareamento', { ok: true });
    setTimeout(encerrarPareamento, 500);
  });
  remote.on('unpaired', () => { log('aviso', 'A TV recusou o pareamento.'); post('tv:pareamento', { ok: false, erro: 'A TV recusou o pareamento.' }); encerrarPareamento(); });
  try { const p = remote.start(); if (p && p.catch) p.catch((e) => log('aviso', 'pareamento: ' + ((e && e.message) || e))); } catch (e) { log('erro', 'pareamento: ' + e.message); }
}

async function comando(host, acao, parametros) {
  const cert = lerCert();
  if (!cert) { post('tv:resultado', { acao, ok: false, erro: 'Pareie a TV primeiro (botão 1).' }); return; }
  const { operar } = await import('./tv-logica.mjs');
  const remote = new AndroidRemote(host, { cert, service_name: 'Full Control', pairing_port: 6467, remote_port: 6466 });
  let r;
  try { r = await operar({ remote, teclas: RemoteKeyCode, direcao: RemoteDirection, acao, parametros: parametros || {} }); }
  catch (e) { r = { ok: false, erro: 'Falha: ' + ((e && e.message) || e) }; }
  finally { pararDeVez(remote); }
  log(r.ok ? 'info' : 'aviso', `${acao}: ${r.ok ? 'ok' : r.erro}`);
  post('tv:resultado', { acao, ...r });
}

async function diagnostico(host) {
  const d = { node: process.version, arquitetura: process.arch, plataforma: process.platform, certificado_guardado: !!lerCert() };
  try { d.tls_disponivel = typeof require('tls').connect === 'function'; } catch (e) { d.tls_disponivel = 'erro: ' + e.message; }
  try { d.pasta_dados = app.datadir(); } catch (e) { d.pasta_dados = 'erro: ' + e.message; }
  d.tv = host;
  d.porta_6466_comandos = await sondar(host, 6466);
  d.porta_6467_pareamento = await sondar(host, 6467);
  post('tv:diagnostico', d);
}

// Procura TVs na rede: testa a porta 6467 (pareamento de Android TV) em cada endereço da(s) faixa(s) /24 do celular.
function faixasDoCelular(extra) {
  const f = [];
  try {
    const ifs = require('os').networkInterfaces();
    for (const lista of Object.values(ifs)) for (const i of lista || []) {
      if (i.family === 'IPv4' && !i.internal && /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)/.test(i.address)) f.push(i.address.split('.').slice(0, 3).join('.'));
    }
  } catch (_) { /* Android recente pode negar a lista de interfaces */ }
  const origem = f.length ? 'celular' : 'comuns';
  if (!f.length) f.push('192.168.0', '192.168.1', '192.168.15', '192.168.100', '10.0.0');
  for (const e of extra || []) if (/^\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(e) && !f.includes(e)) f.unshift(e);
  return { faixas: [...new Set(f)], origem };
}
let procurando = false;
async function procurarTvs(faixasPedidas) {
  if (procurando) return;
  procurando = true;
  try {
    const { faixas, origem } = faixasPedidas && faixasPedidas.length ? { faixas: faixasPedidas, origem: 'informada' } : faixasDoCelular();
    log('info', `Procurando TVs nas faixas ${faixas.join(', ')}.0/24 (${origem})...`);
    const alvos = [];
    for (const f of faixas) for (let n = 1; n <= 254; n++) alvos.push(`${f}.${n}`);
    const achadas = [];
    let i = 0;
    const trabalhador = async () => { while (i < alvos.length) { const ip = alvos[i++]; if (await sondar(ip, 6467, 700)) achadas.push(ip); } };
    await Promise.all(Array.from({ length: 80 }, trabalhador));
    achadas.sort((a, b) => a.split('.').map(Number).reduce((x, y) => x * 256 + y) - b.split('.').map(Number).reduce((x, y) => x * 256 + y));
    log('info', `Procura terminou: ${achadas.length} TV(s).`);
    post('tv:procura', { ok: true, achadas, faixas, origem });
  } catch (e) { post('tv:procura', { ok: false, erro: String((e && e.message) || e) }); }
  finally { procurando = false; }
}

const ipValido = (ip) => /^(\d{1,3})(\.\d{1,3}){3}$/.test(String(ip || '')) && String(ip).split('.').every((x) => Number(x) <= 255);
channel.on('tv:parear', (m) => { if (!m || !ipValido(m.host)) return post('tv:pareamento', { ok: false, erro: 'IP da TV inválido.' }); parear(m.host); });
channel.on('tv:codigo', (m) => {
  const c = m && String(m.codigo || '').trim();
  if (!sessaoPareamento) return post('tv:pareamento', { ok: false, erro: 'Comece o pareamento de novo (botão 1).' });
  if (!c || !/^[0-9A-Za-z]{6}$/.test(c)) return log('aviso', 'O código tem 6 letras ou números.');
  log('info', 'Enviando o código para a TV...');
  try { sessaoPareamento.remote.sendCode(c.toUpperCase()); } catch (e) { log('erro', 'sendCode: ' + e.message); }
});
channel.on('tv:comando', (m) => {
  if (!m || !ipValido(m.host)) return post('tv:resultado', { acao: m && m.acao, ok: false, erro: 'IP da TV inválido.' });
  if (!['ligar', 'desligar', 'volume', 'mudo', 'estado', 'app'].includes(m.acao)) return post('tv:resultado', { acao: m.acao, ok: false, erro: 'Ação inválida.' });
  comando(m.host, m.acao, m.parametros).catch((e) => post('tv:resultado', { acao: m.acao, ok: false, erro: String((e && e.message) || e) }));
});
channel.on('tv:diagnostico', (m) => { diagnostico(m && ipValido(m.host) ? m.host : '127.0.0.1').catch((e) => log('erro', 'diagnóstico: ' + e.message)); });
channel.on('tv:procurar', (m) => { procurarTvs(m && Array.isArray(m.faixas) ? m.faixas.filter((x) => /^\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(x)) : []); });
const MOTOR_VERSAO = '2026-11-03 · YouTube';
channel.on('tv:status', () => post('tv:status', { pareado: !!lerCert(), versao: MOTOR_VERSAO }));
channel.on('tv:esquecer', () => { try { fs.unlinkSync(arquivoCert()); log('info', 'Certificado apagado. Pareie de novo.'); } catch (_) { log('info', 'Nenhum certificado guardado.'); } });

log('info', 'Parte Node pronta (' + process.version + ').');
