import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { operar } from '../src/tv-logica.js';

const TECLAS = { KEYCODE_HOME: 3, KEYCODE_BACK: 4, KEYCODE_TV: 170, KEYCODE_TV_INPUT: 178, KEYCODE_POWER: 26, KEYCODE_VOLUME_UP: 24, KEYCODE_VOLUME_DOWN: 25, KEYCODE_VOLUME_MUTE: 164 };
const DIRECAO = { SHORT: 3 };
const RAPIDO = { pronto: 80, estado: 80, confirmar: 80, entreTeclas: 1, depois: 1 };

// TV de mentira: depois de start() emite 'ready' e (se estadoInicial != null) 'powered'.
function tvFalsa({ pronta = true, estadoInicial = false, naoMuda = false } = {}) {
  const r = new EventEmitter();
  r.teclas = [];
  r.ligada = estadoInicial;
  r.start = () => { setTimeout(() => { if (!pronta) return; r.emit('ready'); if (estadoInicial !== null) setTimeout(() => r.emit('powered', r.ligada), 5); }, 5); return Promise.resolve(true); };
  r.sendKey = (k, d) => { r.teclas.push([k, d]); if (k === TECLAS.KEYCODE_POWER && !naoMuda) { r.ligada = !r.ligada; setTimeout(() => r.emit('powered', r.ligada), 5); } };
  return r;
}
const op = (remote, acao, parametros) => operar({ remote, teclas: TECLAS, direcao: DIRECAO, acao, parametros, tempos: RAPIDO });

test('ligar com a TV desligada manda POWER uma vez e confirma', async () => {
  const r = tvFalsa({ estadoInicial: false });
  const res = await op(r, 'ligar');
  assert.deepEqual(res, { ok: true, ligada: true, confirmado: true });
  assert.deepEqual(r.teclas, [[26, 3]]);
});
test('ligar com a TV já ligada não manda nada (POWER alterna)', async () => {
  const r = tvFalsa({ estadoInicial: true });
  const res = await op(r, 'ligar');
  assert.equal(res.ok, true); assert.equal(res.ja, true); assert.equal(r.teclas.length, 0);
});
test('desligar com a TV ligada manda POWER; desligada não manda', async () => {
  const a = tvFalsa({ estadoInicial: true }); const ra = await op(a, 'desligar');
  assert.equal(ra.ligada, false); assert.equal(a.teclas.length, 1);
  const b = tvFalsa({ estadoInicial: false }); const rb = await op(b, 'desligar');
  assert.equal(rb.ja, true); assert.equal(b.teclas.length, 0);
});
test('estado de energia desconhecido: NÃO manda POWER (erro explícito)', async () => {
  const r = tvFalsa({ estadoInicial: null });
  const res = await op(r, 'ligar');
  assert.equal(res.ok, false); assert.equal(res.codigo, 'estado_desconhecido'); assert.equal(r.teclas.length, 0);
});
test('POWER sem confirmação do estado: ok, mas confirmado=false', async () => {
  const r = tvFalsa({ estadoInicial: false, naoMuda: true });
  const res = await op(r, 'ligar');
  assert.equal(res.ok, true); assert.equal(res.confirmado, false);
});
test('volume menos 3 passos = 3 teclas VOLUME_DOWN', async () => {
  const r = tvFalsa({ estadoInicial: true });
  const res = await op(r, 'volume', { direcao: 'menos', passos: 3 });
  assert.equal(res.ok, true); assert.deepEqual(r.teclas.map((t) => t[0]), [25, 25, 25]);
});
test('volume mais e limite de 20 passos', async () => {
  const r = tvFalsa({ estadoInicial: true });
  await op(r, 'volume', { direcao: 'mais', passos: 99 });
  assert.equal(r.teclas.length, 20); assert.ok(r.teclas.every((t) => t[0] === 24));
});
test('mudo manda VOLUME_MUTE uma vez', async () => {
  const r = tvFalsa({ estadoInicial: true });
  const res = await op(r, 'mudo');
  assert.equal(res.ok, true); assert.deepEqual(r.teclas, [[164, 3]]);
});
test('volume com a TV desligada dá erro e não manda tecla', async () => {
  const r = tvFalsa({ estadoInicial: false });
  const res = await op(r, 'volume', { direcao: 'mais', passos: 1 });
  assert.equal(res.ok, false); assert.equal(res.codigo, 'tv_desligada'); assert.equal(r.teclas.length, 0);
});
test('TV que não fica pronta: erro sem_conexao (tempo limite, sem travar)', async () => {
  const r = tvFalsa({ pronta: false });
  const t0 = Date.now(); const res = await op(r, 'ligar');
  assert.equal(res.codigo, 'sem_conexao'); assert.ok(Date.now() - t0 < 1000);
});
test("evento 'unpaired' vira erro de pareamento perdido", async () => {
  const r = tvFalsa({ pronta: false });
  r.start = () => { setTimeout(() => r.emit('unpaired'), 5); return Promise.resolve(); };
  const res = await op(r, 'ligar');
  assert.equal(res.codigo, 'despareada');
});
test('ação desconhecida', async () => {
  const res = await op(tvFalsa({ estadoInicial: true }), 'dancar');
  assert.equal(res.ok, false);
});

test('app youtube manda o link do YouTube com a TV ligada', async () => {
  const r = tvFalsa({ estadoInicial: true }); const links = []; r.sendAppLink = (l) => links.push(l);
  const res = await op(r, 'app', { app: 'youtube' });
  assert.equal(res.ok, true); assert.deepEqual(links, ['https://www.youtube.com']); assert.equal(r.teclas.length, 0);
});
test('app com a TV desligada não manda link; app fora da lista é recusado', async () => {
  const a = tvFalsa({ estadoInicial: false }); const la = []; a.sendAppLink = (l) => la.push(l);
  assert.equal((await op(a, 'app', { app: 'youtube' })).codigo, 'tv_desligada'); assert.equal(la.length, 0);
  const b = tvFalsa({ estadoInicial: true }); const lb = []; b.sendAppLink = (l) => lb.push(l);
  assert.equal((await op(b, 'app', { app: 'http://malicioso.example' })).codigo, 'app_desconhecido'); assert.equal(lb.length, 0);
});

test('tecla tv manda KEYCODE_TV; com a TV desligada ou tecla fora da lista não manda nada', async () => {
  const a = tvFalsa({ estadoInicial: true }); const ra = await op(a, 'tecla', { tecla: 'tv' });
  assert.equal(ra.ok, true); assert.deepEqual(a.teclas, [[170, 3]]);
  const b = tvFalsa({ estadoInicial: false }); assert.equal((await op(b, 'tecla', { tecla: 'home' })).codigo, 'tv_desligada'); assert.equal(b.teclas.length, 0);
  const c = tvFalsa({ estadoInicial: true }); assert.equal((await op(c, 'tecla', { tecla: 'reiniciar' })).codigo, 'tecla_desconhecida'); assert.equal(c.teclas.length, 0);
});

test('app netflix e hbo mandam o link de cada um', async () => {
  const r = tvFalsa({ estadoInicial: true }); const links = []; r.sendAppLink = (l) => links.push(l);
  assert.equal((await op(r, 'app', { app: 'netflix' })).ok, true);
  assert.equal((await op(r, 'app', { app: 'hbo' })).ok, true);
  assert.deepEqual(links, ['https://www.netflix.com/title', 'https://play.hbomax.com']);
});
