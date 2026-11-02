import test from 'node:test';
import assert from 'node:assert/strict';
import { hostsDaSubrede, varrer, pacoteWol, subredeDeIp, broadcastDeIp, ipValido } from '../src/rede.js';

test('/24 tem 254 hosts, de .1 a .254', () => {
  const h = hostsDaSubrede('192.168.1.0/24');
  assert.equal(h.length, 254); assert.equal(h[0], '192.168.1.1'); assert.equal(h.at(-1), '192.168.1.254');
});
test('sub-rede inválida ou grande demais é recusada', () => {
  assert.throws(() => hostsDaSubrede('10.0.0.0/8')); assert.throws(() => hostsDaSubrede('abc')); assert.throws(() => hostsDaSubrede('192.168.1.0/33'));
});
test('varrer devolve só os IPs com a porta aberta, em ordem', async () => {
  const abertos = new Set(['192.168.1.212', '192.168.1.9']);
  const r = await varrer('192.168.1.0/24', { sondar: async (ip) => abertos.has(ip) });
  assert.deepEqual(r, ['192.168.1.9', '192.168.1.212']);
});
test('pacote Wake-on-LAN: 102 bytes, 6x0xFF e MAC repetido 16x', () => {
  const p = pacoteWol('0c:91:60:4c:5e:85');
  assert.equal(p.length, 102);
  assert.ok(p.subarray(0, 6).every((b) => b === 0xff));
  for (let i = 0; i < 16; i++) assert.equal(p.subarray(6 + i * 6, 12 + i * 6).toString('hex'), '0c91604c5e85');
  assert.throws(() => pacoteWol('xx'));
});
test('ajudantes de IP', () => {
  assert.equal(subredeDeIp('192.168.1.212'), '192.168.1.0/24'); assert.equal(broadcastDeIp('192.168.1.212'), '192.168.1.255');
  assert.equal(subredeDeIp('abc'), null); assert.equal(ipValido('300.1.1.1'), false); assert.equal(ipValido('10.0.0.1'), true);
});
