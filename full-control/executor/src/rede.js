// Rede local: sondar portas, varrer a sub-rede, identidade (impressão digital do certificado da TV) e Wake-on-LAN.
import net from 'node:net';
import tls from 'node:tls';
import dgram from 'node:dgram';

export const PORTA_COMANDO = 6466;
export const PORTA_PAREAMENTO = 6467;

export function sondarPorta(ip, porta, timeoutMs = 1200) {
  return new Promise((resolve) => {
    const s = net.connect({ host: ip, port: porta });
    const fim = (ok) => { s.destroy(); resolve(ok); };
    s.setTimeout(timeoutMs, () => fim(false));
    s.once('connect', () => fim(true));
    s.once('error', () => fim(false));
  });
}

// Impressão digital (SHA-256) do certificado que a TV apresenta: identifica a TV mesmo se o IP mudar.
export function identidade(ip, porta = PORTA_COMANDO, timeoutMs = 2500) {
  return new Promise((resolve) => {
    let feito = false;
    const fim = (v) => { if (!feito) { feito = true; try { s.destroy(); } catch (_) { /* já fechado */ } resolve(v); } };
    const s = tls.connect({ host: ip, port: porta, rejectUnauthorized: false }, () => {
      const c = s.getPeerCertificate();
      fim(c && c.fingerprint256 ? c.fingerprint256 : null);
    });
    s.setTimeout(timeoutMs, () => fim(null));
    s.once('error', () => fim(null));
  });
}

const aInt = (ip) => ip.split('.').reduce((a, b) => (a << 8) + Number(b), 0) >>> 0;
const deInt = (n) => [24, 16, 8, 0].map((s) => (n >>> s) & 255).join('.');

export function ipValido(ip) { return /^(\d{1,3})(\.\d{1,3}){3}$/.test(String(ip || '')) && String(ip).split('.').every((x) => Number(x) <= 255); }

// "192.168.1.0/24" -> lista de IPs de hosts (sem rede e sem broadcast). Limita a 1022 hosts (/22).
export function hostsDaSubrede(cidr) {
  const [base, p] = String(cidr).split('/');
  const prefixo = Number(p);
  if (!ipValido(base) || !(prefixo >= 22 && prefixo <= 30)) throw new Error('Sub-rede inválida: use algo como 192.168.1.0/24');
  const mascara = (0xFFFFFFFF << (32 - prefixo)) >>> 0;
  const rede = aInt(base) & mascara;
  const total = 2 ** (32 - prefixo);
  const lista = [];
  for (let i = 1; i < total - 1; i++) lista.push(deInt(rede + i));
  return lista;
}

export function subredeDeIp(ip) { return ipValido(ip) ? ip.split('.').slice(0, 3).join('.') + '.0/24' : null; }
export function broadcastDeIp(ip) { return ipValido(ip) ? ip.split('.').slice(0, 3).join('.') + '.255' : null; }

// Varre a sub-rede procurando quem tem a porta aberta (TV com controle remoto ligado).
export async function varrer(cidr, { porta = PORTA_COMANDO, concorrencia = 48, timeoutMs = 700, sondar = sondarPorta } = {}) {
  const fila = hostsDaSubrede(cidr);
  const achados = [];
  let i = 0;
  async function trabalhador() {
    while (i < fila.length) {
      const ip = fila[i++];
      if (await sondar(ip, porta, timeoutMs)) achados.push(ip);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concorrencia, fila.length) }, trabalhador));
  return achados.sort((a, b) => aInt(a) - aInt(b));
}

// Wake-on-LAN: 6 bytes 0xFF + MAC repetido 16x, UDP porta 9.
export function pacoteWol(mac) {
  const limpo = String(mac || '').replace(/[^0-9a-f]/gi, '');
  if (limpo.length !== 12) throw new Error('MAC inválido');
  const bytes = Buffer.from(limpo, 'hex');
  return Buffer.concat([Buffer.alloc(6, 0xff), ...Array.from({ length: 16 }, () => bytes)]);
}

export function enviarWol(mac, broadcast, vezes = 5) {
  return new Promise((resolve, reject) => {
    const pacote = pacoteWol(mac);
    const s = dgram.createSocket('udp4');
    s.once('error', (e) => { try { s.close(); } catch (_) { /* já fechado */ } reject(e); });
    s.bind(() => {
      s.setBroadcast(true);
      let n = 0;
      const enviar = () => {
        s.send(pacote, 9, broadcast, (e) => {
          if (e) { s.close(); return reject(e); }
          if (++n >= vezes) { s.close(); return resolve(); }
          setTimeout(enviar, 120);
        });
      };
      enviar();
    });
  });
}

export const rede = { sondar: sondarPorta, identidade, varrer, wol: enviarWol };
