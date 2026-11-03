// Lógica de falar com a TV (Android TV Remote v2), sem criar conexão: recebe o "controle remoto" já pronto.
// Assim dá para testar sem TV. Regra de ouro: KEYCODE_POWER ALTERNA liga/desliga, então só se manda depois de
// saber o estado pelo evento 'powered'. Estado desconhecido = erro, nunca "chute".
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));

// Aplicativos que o Full Control sabe abrir (nome -> link). Para acrescentar um, confirme antes que a TV abre esse link.
export const APPS_DA_TV = { youtube: 'https://www.youtube.com' };

// Teclas de navegação que o Full Control sabe mandar (nome -> tecla do controle).
export const TECLAS_DA_TV = { home: 'KEYCODE_HOME', voltar: 'KEYCODE_BACK', tv: 'KEYCODE_TV', entrada: 'KEYCODE_TV_INPUT', canal_mais: 'KEYCODE_CHANNEL_UP', canal_menos: 'KEYCODE_CHANNEL_DOWN' };

export const TEMPOS_PADRAO = { pronto: 9000, estado: 2500, confirmar: 5000, entreTeclas: 120, depois: 350 };

function aguardar(remote, evento, ms) {
  return new Promise((resolve) => {
    const t = setTimeout(() => { remote.off(evento, f); resolve(undefined); }, ms);
    const f = (v) => { clearTimeout(t); resolve(v === undefined ? true : v); };
    remote.once(evento, f);
  });
}

export async function operar({ remote, teclas, direcao, acao, parametros = {}, tempos = {} }) {
  const T = { ...TEMPOS_PADRAO, ...tempos };
  let ligada = null;
  remote.on('powered', (p) => { ligada = !!p; });
  let despareada = false;
  remote.on('unpaired', () => { despareada = true; });

  const prontoP = aguardar(remote, 'ready', T.pronto);
  const iniciou = remote.start();
  if (iniciou && iniciou.catch) iniciou.catch(() => {});
  const pronto = await prontoP;
  if (despareada) return { ok: false, codigo: 'despareada', erro: 'A TV não reconhece mais este pareamento. Refaça o pareamento da TV.' };
  if (!pronto) return { ok: false, codigo: 'sem_conexao', erro: 'A TV não respondeu na rede.' };

  // O estado de energia chega logo depois do 'ready'.
  const limite = Date.now() + T.estado;
  while (ligada === null && Date.now() < limite) await pausa(50);

  const tecla = (k) => remote.sendKey(k, direcao.SHORT);
  let r;
  if (acao === 'estado') {
    r = ligada === null ? { ok: false, codigo: 'estado_desconhecido', erro: 'Não consegui saber se a TV está ligada.' } : { ok: true, ligada };
  } else if (acao === 'ligar' || acao === 'desligar') {
    const querLigada = acao === 'ligar';
    if (ligada === null) return { ok: false, codigo: 'estado_desconhecido', erro: 'Não consegui saber se a TV está ligada; por segurança não enviei o comando (ele alterna liga/desliga).' };
    if (ligada === querLigada) {
      r = { ok: true, ligada, ja: true };
    } else {
      const mudou = aguardar(remote, 'powered', T.confirmar);
      tecla(teclas.KEYCODE_POWER);
      const novo = await mudou;
      r = { ok: true, ligada: novo === undefined ? querLigada : !!novo, confirmado: novo !== undefined };
    }
  } else if (acao === 'volume' || acao === 'mudo') {
    if (ligada === false) return { ok: false, codigo: 'tv_desligada', erro: 'A TV está desligada.' };
    if (acao === 'mudo') {
      tecla(teclas.KEYCODE_VOLUME_MUTE);
    } else {
      const k = parametros.direcao === 'mais' ? teclas.KEYCODE_VOLUME_UP : teclas.KEYCODE_VOLUME_DOWN;
      const passos = Math.min(20, Math.max(1, Number(parametros.passos) || 1));
      for (let i = 0; i < passos; i++) { tecla(k); if (i < passos - 1) await pausa(T.entreTeclas); }
    }
    r = { ok: true, ligada };
  } else if (acao === 'tecla') {
    const nome = TECLAS_DA_TV[String(parametros.tecla || '')];
    if (!nome || teclas[nome] === undefined) return { ok: false, codigo: 'tecla_desconhecida', erro: 'Tecla não disponível: ' + parametros.tecla };
    if (ligada === false) return { ok: false, codigo: 'tv_desligada', erro: 'A TV está desligada.' };
    tecla(teclas[nome]);
    r = { ok: true, ligada, tecla: parametros.tecla };
  } else if (acao === 'app') {
    // Abre um aplicativo da TV por link (Android TV Remote v2: "app link"). Só aplicativos da lista abaixo, nunca um link qualquer.
    const link = APPS_DA_TV[String(parametros.app || '')];
    if (!link) return { ok: false, codigo: 'app_desconhecido', erro: 'Aplicativo não disponível: ' + parametros.app };
    if (ligada === false) return { ok: false, codigo: 'tv_desligada', erro: 'A TV está desligada. Ligue a TV primeiro.' };
    remote.sendAppLink(link);
    r = { ok: true, ligada, app: parametros.app };
  } else {
    return { ok: false, codigo: 'acao', erro: 'Ação desconhecida para a TV: ' + acao };
  }
  await pausa(T.depois);   // dá tempo da TV receber a última tecla
  return r;
}
