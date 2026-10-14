// WhatsApp (WuzAPI): vigia de saúde. Chamado a cada 10 min pelo cron 'whatsapp-vigia' (mesma função whatsapp-agendadas, corpo { tarefa: "vigia" }).
// 1) "Toca" o servidor (GET /admin/users): isso também impede hospedagens grátis de dormirem por falta de acesso.
// 2) Confere se cada sessão marcada como conectada continua logada.
// Só alerta depois de 2 falhas seguidas (a regra fica no banco: whatsapp_saude_registrar), lembra a cada 6 h e avisa quando volta.
// Alertas: registro em whatsapp_saude_estado/eventos (a tela do master lê), aviso na tela e Telegram. Queda de várias sessões vira UMA mensagem para o master.
import { type Cfg, cfgDoAmbiente, wz } from "./envio.ts";

type Env = { get(k: string): string | undefined };

async function telegram(env: Env, chatId: number | null, texto: string) {
  const tg = (env.get("TELEGRAM_BOT_TOKEN") ?? "").trim();
  if (!tg || !chatId) return false;
  try {
    const r = await fetch(`https://api.telegram.org/bot${tg}/sendMessage`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ chat_id: chatId, text: texto }) });
    return r.ok;
  } catch (_) { return false; }
}

export function detalheServidor(r: { status: number; json: any }): string {
  if (r.status === 0) return String(r.json?.error ?? "Servidor inacessível");
  if (r.status === 401 || r.status === 403) return "O servidor recusou o token de admin (confira o segredo WUZAPI_ADMIN_TOKEN)";
  return "Servidor com erro (HTTP " + r.status + ")";
}

export async function rodarVigia(sb: any, env: Env) {
  const cfg: Cfg | null = cfgDoAmbiente(env);
  if (!cfg) return { servidor: "nao_configurado" };
  const master: string[] = [];
  const out: Record<string, unknown> = {};
  const registrar = async (chave: string, user: string | null, ok: boolean, detalhe: string): Promise<string | null> => {
    const { data, error } = await sb.rpc("whatsapp_saude_registrar", { p_chave: chave, p_user: user, p_ok: ok, p_detalhe: detalhe });
    if (error) { console.error("vigia:", error.message); return null; }
    return data as string | null;
  };

  // 1) servidor
  const srv = await wz.saude(cfg);
  const detSrv = srv.ok ? "No ar" : detalheServidor(srv);
  const acaoSrv = await registrar("servidor", null, srv.ok, detSrv);
  out.servidor = srv.ok ? "ok" : detSrv;
  if (acaoSrv === "alertar") master.push(`⚠️ WhatsApp: o servidor do WuzAPI não está respondendo.\n${detSrv}\nAs mensagens programadas ficam na fila e saem quando ele voltar.`);
  if (acaoSrv === "lembrar") master.push(`⚠️ Lembrete: o servidor do WuzAPI continua fora do ar.\n${detSrv}`);
  if (acaoSrv === "recuperou") master.push("✅ WhatsApp: o servidor do WuzAPI voltou ao normal.");

  // 2) sessões (só faz sentido com o servidor no ar)
  if (srv.ok) {
    const { data: contas } = await sb.from("whatsapp_contas").select("user_id, telefone").eq("status", "conectada");
    const caidas: string[] = [];
    for (const c of contas ?? []) {
      const { data: token } = await sb.rpc("whatsapp_token", { p_user: c.user_id });
      if (!token) continue;
      const st = await wz.status(cfg, token);
      if (!st.ok) continue;   // erro do servidor não prova que a sessão caiu; o toque do servidor acima cuida disso
      const logado = st.json?.data?.LoggedIn === true;
      const acao = await registrar("sessao:" + c.user_id, c.user_id, logado, logado ? "Conectada" : "Sessão desconectada: precisa ler o QR de novo");
      if (acao === "alertar") {
        await sb.from("whatsapp_contas").update({ status: "desconectada", ultimo_erro: "A sessão do WhatsApp caiu (o servidor reiniciou ou o WhatsApp desconectou). Leia o QR de novo para continuar.", atualizado_em: new Date().toISOString() }).eq("user_id", c.user_id);
        const { data: chat } = await sb.rpc("whatsapp_chat_usuario", { p_user: c.user_id });
        await telegram(env, chat ?? null, "⚠️ Seu WhatsApp no Taskfull desconectou. Abra a aba WhatsApp e leia o QR de novo. As mensagens programadas esperam você reconectar.");
        caidas.push(c.telefone ? "+" + c.telefone : c.user_id.slice(0, 8));
      }
    }
    if (caidas.length) master.push(`⚠️ WhatsApp: ${caidas.length === 1 ? "1 sessão caiu" : caidas.length + " sessões caíram"} (${caidas.join(", ")}). ${caidas.length > 1 ? "Provável reinício do servidor." : ""} ${caidas.length === 1 ? "A pessoa" : "As pessoas"} já ${caidas.length === 1 ? "foi avisada" : "foram avisadas"} para ler o QR de novo.`.replace(/\s+/g, " ").trim());
    out.sessoes_verificadas = (contas ?? []).length; out.sessoes_caidas = caidas.length;
  }

  if (master.length) {
    const { data: chat } = await sb.rpc("whatsapp_chat_master");
    out.telegram_master = await telegram(env, chat ?? null, master.join("\n\n"));
  }
  // limpeza do histórico de eventos (90 dias)
  await sb.from("whatsapp_saude_eventos").delete().lt("em", new Date(Date.now() - 90 * 86400_000).toISOString());
  return out;
}
