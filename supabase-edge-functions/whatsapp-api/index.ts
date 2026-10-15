// WhatsApp (WuzAPI) — API usada pela tela do Taskfull. verify_jwt = true (o token de quem chamou identifica a pessoa).
// POST { acao: "estado" | "conectar" | "qr" | "desconectar" | "enviar" | "cancelar", ... }. Sempre responde 200 com { ok, erro, ... }.
// Só quem o master liberou (recurso "whatsapp") usa. O envio programado é feito por whatsapp-agendadas (cron a cada minuto).
// Segredos: WUZAPI_URL e WUZAPI_ADMIN_TOKEN. O token de cada pessoa no WuzAPI fica no Vault (RPCs whatsapp_salvar_token / whatsapp_token).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { cfgDoAmbiente, enviarMensagem, normalizarTelefone, wz } from "./envio.ts";

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Content-Type": "application/json" };
const resp = (o: Record<string, unknown>, status = 200) => new Response(JSON.stringify(o), { status, headers: CORS });
const admin = createClient(URL_SB, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const MAX_PENDENTES = 200;

function hex(n: number): string { const b = new Uint8Array(n); crypto.getRandomValues(b); return [...b].map((x) => x.toString(16).padStart(2, "0")).join(""); }
function numeroDoJid(jid: unknown): string | null { const d = String(jid ?? "").split("@")[0].split(":")[0].replace(/\D/g, ""); return d || null; }

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const auth = req.headers.get("Authorization");
  if (!auth) return resp({ erro: "Sem autenticação." }, 401);
  const { data: { user } } = await createClient(URL_SB, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } }).auth.getUser();
  if (!user) return resp({ erro: "Sessão inválida." }, 401);
  let b: any = {};
  try { b = await req.json(); } catch (_) { /* sem corpo */ }

  const { data: liberado } = await admin.rpc("tem_recurso", { p_user: user.id, p_recurso: "whatsapp" });
  if (liberado !== true) return resp({ ok: false, erro: "O WhatsApp é um serviço pago, ainda não liberado para a sua conta. Peça a liberação ao administrador do Taskfull." });

  const cfg = cfgDoAmbiente(Deno.env);
  const conta = async () => (await admin.from("whatsapp_contas").select("id, status, telefone, jid, limite_diario, consentimento_em, ultimo_erro").eq("user_id", user.id).maybeSingle()).data;
  const token = async () => (await admin.rpc("whatsapp_token", { p_user: user.id })).data as string | null;
  const reconectou = () => admin.rpc("whatsapp_saude_registrar", { p_chave: "sessao:" + user.id, p_user: user.id, p_ok: true, p_detalhe: "Reconectada" });   // fecha o alerta de sessão caída
  const marcar = (campos: Record<string, unknown>) => admin.from("whatsapp_contas").update({ ...campos, atualizado_em: new Date().toISOString() }).eq("user_id", user.id);

  try {
    switch (b.acao) {
      case "estado": {
        let c = await conta();
        if (c && cfg) {
          const t = await token();
          if (t) {
            const st = await wz.status(cfg, t);
            if (st.ok) {
              const logado = (st.json?.data?.loggedIn ?? st.json?.data?.LoggedIn) === true;
              const novo = logado ? "conectada" : (c.status === "aguardando_qr" ? "aguardando_qr" : "desconectada");
              if (novo !== c.status) { await marcar({ status: novo }); c = { ...c, status: novo }; if (novo === "conectada") await reconectou(); }
            }
          }
        }
        const { data: hoje } = await admin.rpc("whatsapp_enviadas_hoje", { p_user: user.id });
        const { data: srv } = await admin.from("whatsapp_saude_estado").select("ok, desde").eq("chave", "servidor").maybeSingle();
        return resp({ ok: true, configurado: !!cfg, conta: c, enviadas_hoje: hoje ?? 0, servico: srv ? { ok: srv.ok, desde: srv.desde } : { ok: true } });
      }

      case "conectar": {
        if (!cfg) return resp({ ok: false, erro: "O servidor do WhatsApp ainda não foi configurado pelo administrador." });
        if (b.consentimento !== true) return resp({ ok: false, erro: "É preciso aceitar o aviso de uso antes de conectar." });
        let t = await token();
        if (!t) {
          t = hex(24);
          const novo = await wz.criarUsuario(cfg, "taskfull-" + user.id.slice(0, 8), t);
          if (!novo.ok && !/already|exists|duplicate/i.test(wz.erro(novo))) return resp({ ok: false, erro: "Não consegui criar a conta no servidor do WhatsApp: " + wz.erro(novo) });
          if (!novo.ok) return resp({ ok: false, erro: "Esta conta já existe no servidor do WhatsApp, mas sem credencial guardada. Peça ao administrador para removê-la lá." });
          const { error } = await admin.rpc("whatsapp_salvar_token", { p_user: user.id, p_workspace: b.workspace_id ?? null, p_token: t });
          if (error) return resp({ ok: false, erro: "Não consegui guardar a credencial: " + error.message });
        }
        await marcar({ consentimento_em: new Date().toISOString(), status: "aguardando_qr", ultimo_erro: null });
        const c = await wz.conectar(cfg, t);
        if (!c.ok && !/already connected/i.test(wz.erro(c))) { await marcar({ status: "erro", ultimo_erro: wz.erro(c) }); return resp({ ok: false, erro: "Não consegui iniciar a conexão: " + wz.erro(c) }); }
        return resp({ ok: true });
      }

      case "qr": {
        if (!cfg) return resp({ ok: false, erro: "Servidor do WhatsApp não configurado." });
        const t = await token();
        if (!t) return resp({ ok: false, erro: "Conecte primeiro." });
        const st = await wz.status(cfg, t);
        if (st.ok && (st.json?.data?.loggedIn ?? st.json?.data?.LoggedIn) === true) {
          const jid = st.json?.data?.jid ?? st.json?.data?.Jid ?? st.json?.data?.JID ?? null;
          await marcar({ status: "conectada", jid, telefone: numeroDoJid(jid), ultimo_erro: null });
          await reconectou();
          return resp({ ok: true, conectada: true, telefone: numeroDoJid(jid) });
        }
        if (st.ok && (st.json?.data?.connected ?? st.json?.data?.Connected) !== true) await wz.conectar(cfg, t);   // sessão caiu: reabre para gerar um QR novo
        const q = await wz.qr(cfg, t);
        const qr = q.json?.data?.QRCode ?? q.json?.data?.qrcode ?? null;
        return resp({ ok: true, conectada: false, qr: qr || null });
      }

      case "desconectar": {
        const t = await token();
        if (cfg && t) await wz.sair(cfg, t);
        await marcar({ status: "desconectada" });
        await admin.rpc("whatsapp_cancelar_usuario", { p_user: user.id });
        return resp({ ok: true });
      }

      case "enviar": {
        const c = await conta();
        if (!c || c.status !== "conectada") return resp({ ok: false, erro: "Conecte o WhatsApp antes de enviar." });
        if (!cfg) return resp({ ok: false, erro: "Servidor do WhatsApp não configurado." });
        const fone = normalizarTelefone(b.telefone);
        if (!fone) return resp({ ok: false, erro: "Número inválido. Use DDD e número, ex.: (81) 99999-0000." });
        const texto = String(b.texto ?? "").trim();
        if (!texto) return resp({ ok: false, erro: "Escreva a mensagem." });
        if (texto.length > 1500) return resp({ ok: false, erro: "Mensagem muito longa (máximo 1500 caracteres)." });
        let quando = new Date();
        if (b.quando) {
          quando = new Date(b.quando);
          if (isNaN(quando.getTime())) return resp({ ok: false, erro: "Data e hora inválidas." });
          if (quando.getTime() < Date.now() - 2 * 60_000) return resp({ ok: false, erro: "Essa data e hora já passaram." });
          if (quando.getTime() > Date.now() + 366 * 86400_000) return resp({ ok: false, erro: "Escolha uma data dentro de 1 ano." });
        }
        const imediata = quando.getTime() <= Date.now() + 20_000;
        const { count } = await admin.from("whatsapp_mensagens").select("id", { count: "exact", head: true }).eq("user_id", user.id).eq("status", "agendada");
        if ((count ?? 0) >= MAX_PENDENTES) return resp({ ok: false, erro: `Você já tem ${MAX_PENDENTES} mensagens programadas. Cancele ou espere algumas saírem.` });
        const { data: m, error } = await admin.from("whatsapp_mensagens").insert({
          user_id: user.id, conta_id: c.id, telefone: fone, nome: String(b.nome ?? "").slice(0, 80), texto,
          enviar_em: (imediata ? new Date() : quando).toISOString(), status: imediata ? "enviando" : "agendada",
          tentativas: imediata ? 1 : 0, reservada_em: imediata ? new Date().toISOString() : null,
          origem: ["manual", "agenda", "atividade"].includes(b.origem) ? b.origem : "manual", origem_id: b.origem_id ?? null,
        }).select().single();
        if (error) return resp({ ok: false, erro: "Não consegui salvar a mensagem: " + error.message });
        if (!imediata) return resp({ ok: true, status: "agendada", id: m.id });
        const r = await enviarMensagem(admin, cfg, m);
        return resp({ ok: r.status !== "erro", status: r.status, erro: r.erro, id: m.id });
      }

      case "cancelar": {
        const { data, error } = await admin.from("whatsapp_mensagens").update({ status: "cancelada", erro: "Cancelada por você" })
          .eq("id", b.id).eq("user_id", user.id).eq("status", "agendada").select("id");
        if (error) return resp({ ok: false, erro: error.message });
        return resp({ ok: (data ?? []).length > 0, erro: (data ?? []).length ? undefined : "Esta mensagem não está mais aguardando envio." });
      }

      default:
        return resp({ ok: false, erro: "Ação desconhecida." });
    }
  } catch (e) {
    console.error("whatsapp-api:", e);
    return resp({ ok: false, erro: "Erro inesperado: " + String((e as Error)?.message || e).slice(0, 160) });
  }
});
