// WhatsApp (WuzAPI) — envia as mensagens programadas que já chegaram na hora.
// Chamada a cada minuto pelo pg_cron (job 'whatsapp-agendadas', via pg_net, com a chave anon). verify_jwt = true.
// Com corpo { tarefa: "vigia" } (job 'whatsapp-vigia', a cada 5 min) faz a checagem de saúde em vez de enviar (ver vigia.ts).
// Proteções: no máximo 5 mensagens por rodada, 4 a 9 s de intervalo entre elas, e o limite diário/checagem do número ficam em enviarMensagem.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { cfgDoAmbiente, enviarMensagem } from "./envio.ts";
import { rodarVigia } from "./vigia.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const POR_RODADA = 5;
const espera = (min: number, max: number) => new Promise((r) => setTimeout(r, (min + Math.random() * (max - min)) * 1000));

Deno.serve(async (req) => {
  let corpo: { tarefa?: string } = {};
  try { corpo = await req.json(); } catch (_) { /* sem corpo */ }
  if (corpo.tarefa === "vigia") return Response.json(await rodarVigia(sb, Deno.env));   // cron 'whatsapp-vigia', a cada 5 min
  const cfg = cfgDoAmbiente(Deno.env);
  const { data, error } = await sb.rpc("whatsapp_reservar", { p_limite: POR_RODADA });
  if (error) { console.error("whatsapp-agendadas:", error.message); return Response.json({ erro: error.message }, { status: 500 }); }
  const lista = (data ?? []) as any[];
  if (!lista.length) return Response.json({ enviadas: 0 });
  let enviadas = 0;
  for (let i = 0; i < lista.length; i++) {
    if (i > 0) await espera(4, 9);
    if (!cfg) {   // servidor não configurado: devolve para a fila sem gastar tentativa
      await sb.from("whatsapp_mensagens").update({ status: "agendada", tentativas: Math.max(0, (lista[i].tentativas ?? 1) - 1), erro: "Servidor do WhatsApp não configurado" }).eq("id", lista[i].id);
      continue;
    }
    const r = await enviarMensagem(sb, cfg, lista[i]);
    if (r.status === "enviada") enviadas++;
  }
  return Response.json({ reservadas: lista.length, enviadas });
});
