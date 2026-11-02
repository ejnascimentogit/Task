// Log simples com hora. Nunca imprima a chave do servidor nem o certificado da TV.
export function log(nivel, msg, extra) {
  const linha = `${new Date().toISOString()} [${nivel}] ${msg}` + (extra ? ' ' + JSON.stringify(extra) : '');
  (nivel === 'erro' ? console.error : console.log)(linha);
}
