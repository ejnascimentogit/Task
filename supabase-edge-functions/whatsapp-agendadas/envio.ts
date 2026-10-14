// WhatsApp (WuzAPI): cliente da API e envio de uma mensagem com as proteções contra bloqueio.
// Sem nada específico do Deno (só fetch/crypto), para dar para testar com Node.
// Existe em duas cópias idênticas (whatsapp-api/ e whatsapp-agendadas/), porque cada Edge Function é publicada com os próprios arquivos.
// Segredos da função (Supabase → Edge Functions → Secrets): WUZAPI_URL (ex.: https://wuzapi.seudominio.com, sem barra no fim) e WUZAPI_ADMIN_TOKEN.
// Cabeçalhos: o token de usuário vai em "token" e o de admin em "Authorization" (a documentação do WuzAPI mistura os nomes: confirmar no servidor real).

export type Cfg = { url: string; admin: string };
export type Resp = { ok: boolean; status: number; json: any };

export function cfgDoAmbiente(env: { get(k: string): string | undefined }): Cfg | null {
  const url = (env.get("WUZAPI_URL") ?? "").trim().replace(/\/+$/, "");
  const admin = (env.get("WUZAPI_ADMIN_TOKEN") ?? "").trim();
  return url && admin ? { url, admin } : null;
}

async function chamar(cfg: Cfg, caminho: string, o: { metodo?: string; token?: string; admin?: boolean; corpo?: unknown } = {}): Promise<Resp> {
  const headers: Record<string, string> = { "Content-Type": "application/json", "Accept": "application/json" };
  if (o.admin) headers["Authorization"] = cfg.admin; else if (o.token) headers["token"] = o.token;
  try {
    const r = await fetch(cfg.url + caminho, {
      method: o.metodo ?? (o.corpo ? "POST" : "GET"), headers,
      body: o.corpo ? JSON.stringify(o.corpo) : undefined, signal: AbortSignal.timeout(20000),
    });
    let json: any = null;
    try { json = await r.json(); } catch (_) { /* sem corpo JSON */ }
    return { ok: r.ok && json?.success !== false, status: r.status, json };
  } catch (e) {
    return { ok: false, status: 0, json: { error: "Servidor do WhatsApp inacessível: " + String((e as Error)?.message || e).slice(0, 120) } };
  }
}
const msgErro = (r: Resp) => String(r.json?.error ?? r.json?.message ?? r.json?.data?.Details ?? ("HTTP " + r.status)).slice(0, 200);

export const wz = {
  criarUsuario: (c: Cfg, nome: string, token: string) => chamar(c, "/admin/users", { admin: true, corpo: { name: nome, token, events: "ReadReceipt" } }),
  conectar: (c: Cfg, token: string) => chamar(c, "/session/connect", { token, corpo: { Subscribe: ["ReadReceipt"], Immediate: true } }),
  status: (c: Cfg, token: string) => chamar(c, "/session/status", { token }),
  qr: (c: Cfg, token: string) => chamar(c, "/session/qr", { token }),
  sair: (c: Cfg, token: string) => chamar(c, "/session/logout", { token, corpo: {} }),
  checar: (c: Cfg, token: string, fone: string) => chamar(c, "/user/check", { token, corpo: { Phone: [fone] } }),
  texto: (c: Cfg, token: string, fone: string, corpo: string) => chamar(c, "/chat/send/text", { token, corpo: { Phone: fone, Body: corpo } }),
  erro: msgErro,
};

// Aceita "(81) 99999-0000", "81999990000", "+55 81 99999-0000"... e devolve só dígitos com o DDI (padrão Brasil, 55).
// Com "+" (ou "00") na frente o país é o que a pessoa digitou; sem isso, 10 ou 11 dígitos são DDD + número do Brasil.
export function normalizarTelefone(bruto: string): string | null {
  const texto = String(bruto ?? "").trim();
  const internacional = /^(\+|00)/.test(texto);
  let d = texto.replace(/\D/g, "").replace(/^00/, "");
  if (!internacional && (d.length === 10 || d.length === 11)) d = "55" + d;
  if (d.length < 11 || d.length > 15) return null;
  if (d.startsWith("55") && d.length !== 12 && d.length !== 13) return null;
  return d;
}

export function inicioDoProximoDia(): Date {   // 00:05 do dia seguinte em Brasília (UTC-3, sem horário de verão)
  const agora = new Date(Date.now() - 3 * 3600_000);
  const amanha = Date.UTC(agora.getUTCFullYear(), agora.getUTCMonth(), agora.getUTCDate() + 1, 0, 5);
  return new Date(amanha + 3 * 3600_000);
}

// Envia uma mensagem já reservada (status "enviando"). Tudo que pode dar errado vira status e texto na própria linha.
// sb = cliente do Supabase com a chave de serviço.
export async function enviarMensagem(sb: any, cfg: Cfg, m: any): Promise<{ status: string; erro?: string }> {
  const fecha = async (campos: Record<string, unknown>) => {
    const { error } = await sb.from("whatsapp_mensagens").update(campos).eq("id", m.id);
    if (error) console.error("whatsapp: não consegui gravar o resultado:", error.message);
    return { status: String(campos.status), erro: campos.erro as string | undefined };
  };
  const { data: liberado } = await sb.rpc("tem_recurso", { p_user: m.user_id, p_recurso: "whatsapp" });
  if (liberado !== true) return fecha({ status: "cancelada", erro: "Serviço não liberado para esta conta" });

  const { data: conta } = await sb.from("whatsapp_contas").select("id, status, limite_diario").eq("user_id", m.user_id).maybeSingle();
  if (!conta || conta.status !== "conectada") return fecha({ status: "erro", erro: "O WhatsApp não está conectado. Conecte de novo e reenvie." });

  const { data: hoje } = await sb.rpc("whatsapp_enviadas_hoje", { p_user: m.user_id });
  // a própria mensagem já conta como "enviando"; o limite vale para as de antes dela
  if (typeof hoje === "number" && hoje - 1 >= conta.limite_diario) {
    return fecha({ status: "agendada", enviar_em: inicioDoProximoDia().toISOString(), tentativas: Math.max(0, (m.tentativas ?? 1) - 1), erro: `Adiada: limite de ${conta.limite_diario} mensagens por dia` });
  }
  const { data: token } = await sb.rpc("whatsapp_token", { p_user: m.user_id });
  if (!token) return fecha({ status: "erro", erro: "Conta do WhatsApp sem credencial. Desconecte e conecte de novo." });

  const fone = normalizarTelefone(m.telefone);
  if (!fone) return fecha({ status: "erro", erro: "Número inválido" });
  const chk = await wz.checar(cfg, token, fone);
  if (chk.status === 0 || chk.status >= 500) return tentarDeNovo(fecha, m, wz.erro(chk));
  const u = chk.json?.data?.Users?.[0];
  if (chk.ok && u && u.IsInWhatsapp === false) return fecha({ status: "erro", erro: "Este número não tem WhatsApp" });
  const destino = String(u?.JID ?? "").split("@")[0].split(":")[0] || fone;   // o JID já vem com o formato certo (ex.: nono dígito)

  const r = await wz.texto(cfg, token, destino, String(m.texto));
  if (r.ok) return fecha({ status: "enviada", enviado_em: new Date().toISOString(), erro: null });
  const erro = wz.erro(r);
  if (/not (logged|connected)|no session|disconnected/i.test(erro) || r.status === 401) {
    await sb.from("whatsapp_contas").update({ status: "desconectada", ultimo_erro: erro, atualizado_em: new Date().toISOString() }).eq("id", conta.id);
    return fecha({ status: "erro", erro: "O WhatsApp foi desconectado. Conecte de novo." });
  }
  return tentarDeNovo(fecha, m, erro);
}

function tentarDeNovo(fecha: (c: Record<string, unknown>) => Promise<{ status: string; erro?: string }>, m: any, erro: string) {
  if ((m.tentativas ?? 1) < 3) return fecha({ status: "agendada", enviar_em: new Date(Date.now() + 2 * 60_000).toISOString(), erro: "Nova tentativa em 2 min: " + erro });
  return fecha({ status: "erro", erro });
}
