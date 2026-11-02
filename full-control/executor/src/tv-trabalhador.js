// Processo filho: fala com UMA TV e termina. A biblioteca reconecta sozinha para sempre (o stop() dela não para),
// então cada operação roda isolada e o processo principal mata este processo ao final ou no tempo limite.
import { AndroidRemote, RemoteKeyCode, RemoteDirection } from 'androidtv-remote';
import { operar } from './tv-logica.js';

const sair = (m) => { process.send({ tipo: 'resultado', ...m }, () => process.exit(0)); };
process.on('uncaughtException', (e) => sair({ ok: false, codigo: 'falha', erro: 'Falha ao falar com a TV: ' + (e && e.message) }));
process.on('unhandledRejection', () => { /* a biblioteca rejeita promessas soltas ao perder a conexão */ });

let remotoPareamento = null;
process.on('message', async (m) => {
  try {
    if (m.tipo === 'comando') {
      const remote = new AndroidRemote(m.host, { cert: m.cert, service_name: 'Full Control', pairing_port: m.portaPareamento || 6467, remote_port: m.portaComando || 6466 });
      sair(await operar({ remote, teclas: RemoteKeyCode, direcao: RemoteDirection, acao: m.acao, parametros: m.parametros }));
    } else if (m.tipo === 'parear') {
      remotoPareamento = new AndroidRemote(m.host, { service_name: 'Full Control', pairing_port: m.portaPareamento || 6467, remote_port: m.portaComando || 6466 });
      remotoPareamento.on('secret', () => process.send({ tipo: 'aguardando_codigo' }));
      remotoPareamento.on('ready', () => sair({ ok: true, tipo2: 'pareado', certificado: remotoPareamento.getCertificate() }));
      const p = remotoPareamento.start();
      if (p && p.catch) p.catch(() => {});
      Promise.resolve(p).then((v) => { if (v === undefined || v === false) { /* só falha se o 'ready' não vier */ } });
    } else if (m.tipo === 'codigo' && remotoPareamento) {
      remotoPareamento.sendCode(String(m.codigo));
    }
  } catch (e) {
    sair({ ok: false, codigo: 'falha', erro: 'Falha ao falar com a TV: ' + (e && e.message) });
  }
});
