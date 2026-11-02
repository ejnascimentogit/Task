import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { criarTv } from '../src/tv.js';

function filhoFalso(roteiro) {
  const f = new EventEmitter(); f.mortes = 0; f.enviados = [];
  f.kill = () => { f.mortes++; };
  f.send = (m) => { f.enviados.push(m); roteiro && roteiro(f, m); };
  return f;
}

test('executar: devolve o resultado do filho e MATA o filho', async () => {
  const f = filhoFalso((fl, m) => setTimeout(() => fl.emit('message', { tipo: 'resultado', ok: true, ligada: true }), 5));
  const tv = criarTv({ criarFilho: () => f });
  const r = await tv.executar({ host: '1.2.3.4', cert: { key: 'k', cert: 'c' }, acao: 'ligar', parametros: {} });
  assert.equal(r.ok, true); assert.equal(f.mortes >= 1, true); assert.equal(f.enviados[0].tipo, 'comando'); assert.equal(f.enviados[0].host, '1.2.3.4');
});
test('executar: filho que não responde é morto no tempo limite', async () => {
  const f = filhoFalso();
  const tv = criarTv({ criarFilho: () => f });
  const r = await tv.executar({ host: 'x', cert: {}, acao: 'ligar', timeoutMs: 40 });
  assert.equal(r.ok, false); assert.equal(r.codigo, 'timeout'); assert.equal(f.mortes >= 1, true);
});
test('executar: filho que morre sozinho vira erro', async () => {
  const f = filhoFalso((fl) => setTimeout(() => fl.emit('exit', 1), 5));
  const r = await criarTv({ criarFilho: () => f }).executar({ host: 'x', cert: {}, acao: 'ligar' });
  assert.equal(r.ok, false);
});
test('pareamento: etapa 1 espera a TV mostrar o código; etapa 2 devolve o certificado e encerra', async () => {
  const f = filhoFalso((fl, m) => {
    if (m.tipo === 'parear') setTimeout(() => fl.emit('message', { tipo: 'aguardando_codigo' }), 5);
    if (m.tipo === 'codigo') setTimeout(() => fl.emit('message', { tipo: 'resultado', ok: true, certificado: { key: 'K', cert: 'C' } }), 5);
  });
  const tv = criarTv({ criarFilho: () => f });
  const a = await tv.iniciarPareamento('d1', '1.2.3.4');
  assert.equal(a.ok, true); assert.equal(tv.pareamentosAbertos(), 1);
  const b = await tv.enviarCodigo('d1', 'A1B2C3');
  assert.equal(b.ok, true); assert.deepEqual(b.certificado, { key: 'K', cert: 'C' });
  assert.equal(tv.pareamentosAbertos(), 0); assert.equal(f.mortes >= 1, true);
});
test('enviar código sem ter começado: pede para recomeçar', async () => {
  const r = await criarTv({ criarFilho: () => filhoFalso() }).enviarCodigo('d1', 'A1B2C3');
  assert.equal(r.ok, false); assert.match(r.erro, /Comece o pareamento/);
});
