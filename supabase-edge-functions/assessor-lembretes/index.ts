// Assessor pessoal — lembretes automáticos no Telegram.
// Chamado a cada minuto pelo pg_cron (job 'assessor-lembretes'). Idempotente:
// cada compromisso é avisado uma única vez por pessoa (assessor_lembretes_enviados).
import { createClient } from "jsr:@supabase/supabase-js@2";

const TG = (Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "").trim();
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

function quando(min: number): string {
  if (min <= 1) return "agora";
  if (min < 60) return `em ${min} minutos`;
  const h = Math.floor(min / 60), m = min % 60;
  return `em ${h}h${m ? String(m).padStart(2, "0") : ""}`;
}

Deno.serve(async () => {
  const { data, error } = await sb.rpc("assessor_lembretes_pendentes");
  if (error) {
    console.error("assessor-lembretes:", error.message);
    return Response.json({ erro: error.message }, { status: 500 });
  }
  let enviados = 0;
  for (const l of data ?? []) {
    // Marca antes de enviar: se o envio falhar, não repete o aviso a cada minuto.
    const { error: e } = await sb.from("assessor_lembretes_enviados")
      .insert({ agendamento_id: l.agendamento_id, user_id: l.user_id });
    if (e) continue;
    const hora = String(l.hora).slice(0, 5);
    const r = await fetch(`https://api.telegram.org/bot${TG}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: l.chat_id,
        text: `⏰ Lembrete: ${l.titulo}\n${quando(l.minutos_faltando)}, às ${hora}.`,
      }),
    });
    if (r.ok) enviados++;
  }
  return Response.json({ pendentes: (data ?? []).length, enviados });
});
