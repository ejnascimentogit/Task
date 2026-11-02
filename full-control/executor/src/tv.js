// Lado do processo principal: cria o processo filho de cada operação na TV, com tempo limite, e o mata no fim.
import { fork } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const TRABALHADOR = fileURLToPath(new URL('./tv-trabalhador.js', import.meta.url));
const forkPadrao = () => fork(TRABALHADOR, [], { stdio: ['ignore', 'ignore', 'ignore', 'ipc'] });

export function criarTv({ criarFilho = forkPadrao } = {}) {
  const pareamentos = new Map();   // dispositivoId -> { filho, timer }

  function rodar(msg, { timeoutMs = 20000, aoMensagem } = {}) {
    return new Promise((resolve) => {
      const filho = criarFilho();
      let feito = false;
      const fim = (r) => {
        if (feito) return; feito = true; clearTimeout(timer);
        try { filho.kill('SIGKILL'); } catch (_) { /* já terminou */ }
        resolve(r);
      };
      const timer = setTimeout(() => fim({ ok: false, codigo: 'timeout', erro: 'A TV não respondeu a tempo.' }), timeoutMs);
      filho.on('message', (m) => { if (m && m.tipo === 'resultado') fim(m); else if (aoMensagem) aoMensagem(m, fim); });
      filho.on('error', () => fim({ ok: false, codigo: 'falha', erro: 'Falha interna ao falar com a TV.' }));
      filho.on('exit', () => fim({ ok: false, codigo: 'falha', erro: 'O processo da TV terminou sem resposta.' }));
      filho.send(msg);
    });
  }

  return {
    executar: ({ host, cert, acao, parametros, timeoutMs = 25000 }) => rodar({ tipo: 'comando', host, cert, acao, parametros }, { timeoutMs }),

    // 1ª etapa: a TV passa a mostrar o código de 6 caracteres. O processo fica vivo (até 3 min) esperando o código.
    iniciarPareamento(dispositivoId, host) {
      const antigo = pareamentos.get(dispositivoId);
      if (antigo) { clearTimeout(antigo.timer); try { antigo.filho.kill('SIGKILL'); } catch (_) { /* já terminou */ } pareamentos.delete(dispositivoId); }
      return new Promise((resolve) => {
        const filho = criarFilho();
        let respondeu = false;
        const limpar = () => { const s = pareamentos.get(dispositivoId); if (s && s.filho === filho) { clearTimeout(s.timer); pareamentos.delete(dispositivoId); } try { filho.kill('SIGKILL'); } catch (_) { /* já terminou */ } };
        const falhar = (erro) => { limpar(); if (!respondeu) { respondeu = true; resolve({ ok: false, erro }); } };
        const espera = setTimeout(() => falhar('A TV não mostrou o código a tempo.'), 20000);
        const sessao = { filho, timer: setTimeout(limpar, 180000), esperaCodigo: null };
        pareamentos.set(dispositivoId, sessao);
        filho.on('message', (m) => {
          if (m && m.tipo === 'aguardando_codigo' && !respondeu) { respondeu = true; clearTimeout(espera); resolve({ ok: true }); }
          else if (m && m.tipo === 'resultado' && sessao.esperaCodigo) sessao.esperaCodigo(m);
        });
        filho.on('error', () => falhar('Falha interna ao parear.'));
        filho.on('exit', () => { clearTimeout(espera); if (!respondeu) { respondeu = true; resolve({ ok: false, erro: 'O pareamento terminou sem resposta.' }); } });
        filho.send({ tipo: 'parear', host });
      });
    },

    // 2ª etapa: a pessoa digita o código; devolvemos o certificado para guardar no banco.
    enviarCodigo(dispositivoId, codigo) {
      const sessao = pareamentos.get(dispositivoId);
      if (!sessao) return Promise.resolve({ ok: false, erro: 'Comece o pareamento de novo (a TV precisa mostrar o código).' });
      return new Promise((resolve) => {
        const fim = (r) => { clearTimeout(t); clearTimeout(sessao.timer); pareamentos.delete(dispositivoId); try { sessao.filho.kill('SIGKILL'); } catch (_) { /* já terminou */ } resolve(r); };
        const t = setTimeout(() => fim({ ok: false, erro: 'A TV não confirmou o código. Confira e tente de novo.' }), 25000);
        sessao.esperaCodigo = fim;
        sessao.filho.send({ tipo: 'codigo', codigo });
      });
    },
    pareamentosAbertos: () => pareamentos.size,
  };
}
