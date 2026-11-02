import test from 'node:test';
import assert from 'node:assert/strict';
import { criarExecutor } from '../src/executor.js';

const CERT = { cert: { key: 'K', cert: 'C' } };
function montar({ disp, abertos = [], identidades = {}, varridos = [], cred = CERT, tvResultado = { ok: true, ligada: true }, wolAbre = null } = {}) {
  const chamadas = { tv: [], estado: [], wol: [], gravou: [] };
  const abertosSet = new Set(abertos);
  const api = {
    credencialLer: async () => cred,
    estado: async (id, estado, config) => { chamadas.estado.push({ id, estado, config }); },
    credencialGravar: async (id, s) => { chamadas.gravou.push({ id, s }); },
  };
  const tv = {
    executar: async (a) => { chamadas.tv.push(a); return typeof tvResultado === 'function' ? tvResultado(a, chamadas.tv.length) : tvResultado; },
    iniciarPareamento: async (id, host) => { chamadas.parear = { id, host }; return { ok: true }; },
    enviarCodigo: async (id, codigo) => { chamadas.codigo = { id, codigo }; return { ok: true, certificado: { key: 'NK', cert: 'NC' } }; },
  };
  const rede = {
    sondar: async (ip) => abertosSet.has(ip),
    identidade: async (ip) => identidades[ip] || null,
    varrer: async () => varridos,
    wol: async (mac, bc, n) => { chamadas.wol.push({ mac, bc, n }); if (wolAbre) abertosSet.add(wolAbre); },
  };
  const ex = criarExecutor({ api, tv, rede, esperar: async () => {} });
  return { ex, chamadas, disp };
}
const TV = (config = {}) => ({ id: 'd1', nome: 'TV do quarto', protocolo: 'android_tv', tipo: 'tv', config: { ultimo_ip: '192.168.1.212', mac: '0c:91:60:4c:5e:85', broadcast: '192.168.1.255', ...config } });
const cmd = (acao, disp, parametros = {}) => ({ id: 'c1', acao, parametros, dispositivos: [disp] });

test('ligar: TV no último IP -> executa e grava estado e IP', async () => {
  const disp = TV();
  const { ex, chamadas } = montar({ disp, abertos: ['192.168.1.212'], identidades: { '192.168.1.212': 'AA' } });
  const r = await ex.processar(cmd('ligar', disp));
  assert.equal(r.ok, true);
  assert.equal(chamadas.tv[0].host, '192.168.1.212'); assert.equal(chamadas.tv[0].acao, 'ligar');
  assert.deepEqual(chamadas.estado[0].config, { ultimo_ip: '192.168.1.212', identidade: 'AA' }); assert.deepEqual(chamadas.estado[0].estado, { ligada: true });
});
test('IP mudou: acha a mesma TV pela identidade e atualiza o IP', async () => {
  const disp = TV({ identidade: 'AA' });
  const { ex, chamadas } = montar({ disp, abertos: ['192.168.1.99'], varridos: ['192.168.1.50', '192.168.1.99'], identidades: { '192.168.1.50': 'ZZ', '192.168.1.99': 'AA' } });
  const r = await ex.processar(cmd('volume', disp, { direcao: 'mais', passos: 2 }));
  assert.equal(r.ok, true); assert.equal(chamadas.tv[0].host, '192.168.1.99'); assert.equal(chamadas.estado[0].config.ultimo_ip, '192.168.1.99');
});
test('outro aparelho no mesmo IP (identidade diferente) não é tratado como a TV', async () => {
  const disp = TV({ identidade: 'AA' });
  const { ex, chamadas } = montar({ disp, abertos: ['192.168.1.212'], varridos: ['192.168.1.212'], identidades: { '192.168.1.212': 'OUTRA' } });
  const r = await ex.processar(cmd('mudo', disp));
  assert.equal(r.ok, false); assert.equal(chamadas.tv.length, 0);
});
test('sem identidade guardada e duas TVs na rede: não chuta', async () => {
  const disp = TV();
  const { ex, chamadas } = montar({ disp, abertos: [], varridos: ['192.168.1.5', '192.168.1.6'] });
  const r = await ex.processar(cmd('mudo', disp));
  assert.equal(r.ok, false); assert.equal(chamadas.tv.length, 0);
});
test('ligar com a porta fechada: Wake-on-LAN (5 vezes, broadcast certo) e depois liga', async () => {
  const disp = TV();
  const { ex, chamadas } = montar({ disp, abertos: [], wolAbre: '192.168.1.212' });
  const r = await ex.processar(cmd('ligar', disp));
  assert.deepEqual(chamadas.wol, [{ mac: '0c:91:60:4c:5e:85', bc: '192.168.1.255', n: 5 }]);
  assert.equal(r.ok, true); assert.equal(chamadas.tv.length, 1);
});
test('ligar sem achar a TV e sem MAC: erro com a dica de "Consumo elevado"', async () => {
  const disp = TV({ mac: undefined });
  const { ex } = montar({ disp, abertos: [] });
  const r = await ex.processar(cmd('ligar', disp));
  assert.equal(r.ok, false); assert.match(r.erro, /Consumo elevado/);
});
test('volume com a TV fora do ar: erro claro e sem Wake-on-LAN', async () => {
  const disp = TV();
  const { ex, chamadas } = montar({ disp, abertos: [] });
  const r = await ex.processar(cmd('volume', disp, { direcao: 'menos', passos: 3 }));
  assert.equal(r.ok, false); assert.match(r.erro, /desligada|fora da rede/); assert.equal(chamadas.wol.length, 0);
});
test('sem certificado: pede para parear', async () => {
  const disp = TV();
  const { ex } = montar({ disp, abertos: ['192.168.1.212'], cred: {} });
  const r = await ex.processar(cmd('ligar', disp));
  assert.equal(r.ok, false); assert.match(r.erro, /pareada/);
});
test('protocolo sem driver (ainda): erro claro', async () => {
  const disp = { id: 'l1', nome: 'Luz da frente', protocolo: 'tuya', config: {} };
  const { ex } = montar({ disp });
  const r = await ex.processar(cmd('ligar', disp));
  assert.equal(r.ok, false); assert.match(r.erro, /driver/);
});
test('falha da TV é repassada ao app', async () => {
  const disp = TV();
  const { ex } = montar({ disp, abertos: ['192.168.1.212'], tvResultado: { ok: false, erro: 'A TV está desligada.', codigo: 'tv_desligada' } });
  const r = await ex.processar(cmd('volume', disp, { direcao: 'mais', passos: 1 }));
  assert.deepEqual(r, { ok: false, erro: '"TV do quarto": ... '.replace('"TV do quarto": ... ', 'A TV está desligada.') });
});
test('descobrir: lista TVs e marca a que já está cadastrada', async () => {
  const disp = TV({ identidade: 'AA' });
  const { ex } = montar({ disp, varridos: ['192.168.1.99', '192.168.1.150'], identidades: { '192.168.1.99': 'AA', '192.168.1.150': 'BB' } });
  const r = await ex.processar({ id: 'c', acao: 'descobrir', parametros: {}, dispositivos: [] }, [disp]);
  assert.equal(r.ok, true); assert.equal(r.resultado.subrede, '192.168.1.0/24');
  assert.equal(r.resultado.tvs.length, 2); assert.equal(r.resultado.tvs[0].cadastrada_como, 'TV do quarto'); assert.equal(r.resultado.tvs[1].cadastrada_como, null);
});
test('descobrir sem saber qual rede varrer: erro claro', async () => {
  const { ex } = montar({ disp: TV({ ultimo_ip: undefined }) });
  const r = await ex.processar({ id: 'c', acao: 'descobrir', parametros: {}, dispositivos: [] }, [{ id: 'x', nome: 'n', config: {} }]);
  assert.equal(r.ok, false); assert.match(r.erro, /FC_SUBREDE/);
});
test('pareamento em duas etapas: guarda o certificado e nunca devolve segredo no resultado', async () => {
  const disp = TV();
  const { ex, chamadas } = montar({ disp, abertos: ['192.168.1.212'] });
  const a = await ex.processar(cmd('iniciar_pareamento', disp));
  assert.equal(a.ok, true); assert.equal(a.resultado.aguardando_codigo, true); assert.equal(chamadas.parear.host, '192.168.1.212');
  const b = await ex.processar(cmd('enviar_codigo', disp, { codigo: 'A1B2C3' }));
  assert.equal(b.ok, true); assert.equal(chamadas.codigo.codigo, 'A1B2C3');
  assert.deepEqual(chamadas.gravou, [{ id: 'd1', s: { cert: { key: 'NK', cert: 'NC' } } }]);
  assert.equal(JSON.stringify(b).includes('NK'), false);
});
test('comando de grupo: todos os dispositivos, falhas somadas', async () => {
  const d1 = TV(); const d2 = { id: 'd2', nome: 'Luz', protocolo: 'tuya', config: {} };
  const { ex } = montar({ disp: d1, abertos: ['192.168.1.212'] });
  const r = await ex.processar({ id: 'c', acao: 'desligar', parametros: {}, dispositivos: [d1, d2] });
  assert.equal(r.ok, false); assert.match(r.erro, /Luz/);
});
test('exceção inesperada não derruba o servidor', async () => {
  const disp = TV();
  const { ex } = montar({ disp, abertos: ['192.168.1.212'], tvResultado: () => { throw new Error('boom'); } });
  const r = await ex.processar(cmd('ligar', disp));
  assert.equal(r.ok, false); assert.match(r.erro, /inesperado/);
});
