// Testa a parte Node do aplicativo (www/nodejs/index.js) fora do celular, com uma "ponte" de mentira no lugar do plugin.
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createRequire } from 'node:module';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import tls from 'node:tls';

const require = createRequire(import.meta.url);
const Module = require('module');
const pasta = mkdtempSync(path.join(tmpdir(), 'fc-app-'));
const posts = [];
const canal = new EventEmitter();
canal.post = (evento, dados) => { posts.push({ evento, dados }); canal.emit('__post', evento, dados); };
const ponteFalsa = { app: { datadir: () => pasta, on: () => {} }, channel: canal };
const carregar = Module._load;
Module._load = function (request) { if (request === 'bridge') return ponteFalsa; return carregar.apply(this, arguments); };
require(path.resolve('www/nodejs/index.js'));

const esperar = (evento, ms = 20000) => new Promise((res, rej) => {
  const t = setTimeout(() => { canal.off('__post', f); rej(new Error('sem ' + evento)); }, ms);
  const f = (e, d) => { if (e === evento) { clearTimeout(t); canal.off('__post', f); res(d); } };
  canal.on('__post', f);
});

test('a parte Node avisa que está pronta', () => {
  assert.ok(posts.some((p) => p.evento === 'log' && /pronta/.test(p.dados.msg)));
});
test('IP inválido é recusado sem tocar na rede', async () => {
  const w = esperar('tv:pareamento'); canal.emit('tv:parear', { host: 'abc' });
  const r = await w; assert.equal(r.ok, false); assert.match(r.erro, /IP/);
});
test('comando sem pareamento pede para parear', async () => {
  const w = esperar('tv:resultado'); canal.emit('tv:comando', { host: '127.0.0.1', acao: 'ligar' });
  const r = await w; assert.equal(r.ok, false); assert.match(r.erro, /Pareie/);
});
test('ação inválida é recusada', async () => {
  const w = esperar('tv:resultado'); canal.emit('tv:comando', { host: '127.0.0.1', acao: 'dancar' });
  assert.equal((await w).ok, false);
});
test('diagnóstico informa Node, TLS e portas fechadas', async () => {
  const w = esperar('tv:diagnostico'); canal.emit('tv:diagnostico', { host: '127.0.0.1' });
  const d = await w;
  assert.equal(d.tls_disponivel, true); assert.equal(d.porta_6466_comandos, false); assert.equal(d.porta_6467_pareamento, false); assert.equal(d.certificado_guardado, false);
});
test('biblioteca não carrega o systeminformation de verdade (trocado por valor fixo)', () => {
  assert.equal(Object.keys(require.cache).some((k) => /systeminformation/.test(k)), false);
});
test('TV inalcançável: erro em ~9 s e a reconexão infinita da biblioteca é neutralizada', { timeout: 40000 }, async () => {
  const gerador = require(path.resolve('www/nodejs/node_modules/androidtv-remote/dist/certificate/CertificateGenerator.js')).CertificateGenerator;
  const c = gerador.generateFull('t', 'BR', 'PE', 'Recife', 'FC', 'FC');
  const { writeFileSync } = await import('node:fs');
  writeFileSync(path.join(pasta, 'cert.json'), JSON.stringify({ key: c.key, cert: c.cert }));
  let conexoes = 0; const original = tls.connect;
  tls.connect = function () { conexoes++; return original.apply(this, arguments); };
  try {
    const w = esperar('tv:resultado', 30000);
    canal.emit('tv:comando', { host: '127.0.0.1', acao: 'ligar' });
    const r = await w;
    assert.equal(r.ok, false); assert.equal(r.codigo, 'sem_conexao');
    const antes = conexoes;
    await new Promise((res) => setTimeout(res, 4000));   // a biblioteca tentaria de novo a cada ~1 s
    assert.equal(conexoes, antes, `reconectou ${conexoes - antes} vez(es) depois de parar`);
    assert.ok(antes >= 1);
  } finally { tls.connect = original; }
});
