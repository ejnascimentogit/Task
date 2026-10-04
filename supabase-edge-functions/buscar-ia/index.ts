// ══════════════════════════════════════════════════════════════════════════════════════════════
// Edge Function `buscar-ia`: ESTRUTURA PRONTA, NÃO PUBLICADA. A busca com IA do Taskfull está DESLIGADA.
//
// Para ligar (nesta ordem, só quando for decidido):
//   1. Supabase → Edge Functions → Deploy desta função.
//   2. Supabase → Project Settings → Edge Functions → Secrets: ANTHROPIC_API_KEY (conta Anthropic com limite
//      mensal de gasto definido). SUPABASE_URL, SUPABASE_ANON_KEY e SUPABASE_SERVICE_ROLE_KEY já vêm injetados.
//   3. Por workspace, pelo SQL Editor (a tabela não tem policy de escrita, só o dono do app liga):
//        insert into public.busca_ia_config (workspace_id, ativo, limite_mensal_usd)
//        values ('<id do workspace>', true, 1.00)
//        on conflict (workspace_id) do update set ativo = true, limite_mensal_usd = excluded.limite_mensal_usd, updated_at = now();
//
// Por que é diferente da versão do Painel de Implantação (que é de uma empresa só):
//   - A chave da Anthropic é de UMA conta e valeria pra todos os workspaces de todos os usuários do Taskfull.
//     Por isso: liga por workspace + limite mensal em US$ por workspace, conferidos AQUI, no servidor.
//   - Esta função NÃO confia no texto que o navegador manda como "contexto": ela refaz a busca no banco
//     (função buscar_workspace) com o token de quem chamou, então a RLS (is_member) vale. Sem isso, qualquer
//     membro poderia usar a chave como chat grátis, mandando qualquer texto como "candidato".
//   - O uso é gravado com a service role (membro só lê busca_ia_uso), pra ninguém zerar o contador do limite.
// ══════════════════════════════════════════════════════════════════════════════════════════════
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const MODELO = "claude-haiku-4-5-20251001";
const PRECO_INPUT_POR_MILHAO = 1;   // USD, conferir sempre em claude.com/pricing
const PRECO_OUTPUT_POR_MILHAO = 5;  // USD
const MAX_PERGUNTA = 500;
const MAX_CANDIDATOS = 20;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

const SYSTEM_PROMPT = "Você é um assistente interno do Taskfull. Responda à pergunta do usuário em português do Brasil, de forma direta e objetiva (2 a 4 frases), baseando-se SOMENTE nas informações fornecidas: nunca invente nada que não esteja nelas. Quando a resposta vier de uma atividade, cite a data e quem fez. Se as informações não forem suficientes pra responder com confiança, diga claramente que não encontrou isso registrado, sem inventar. ATENÇÃO: o resumo de uma atividade é texto corrido e pode cobrir VÁRIOS assuntos tratados na mesma ocasião; identifique quais frases pertencem a qual assunto antes de responder e inclua só o que for realmente sobre o que foi perguntado.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Sem autenticação." }, 401);

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) return jsonResponse({ error: "Sessão inválida." }, 401);

    const { workspace_id, pergunta, termo_busca } = await req.json();
    if (!workspace_id || !pergunta || typeof pergunta !== "string") return jsonResponse({ error: "Informe workspace_id e pergunta." }, 400);
    if (pergunta.length > MAX_PERGUNTA) return jsonResponse({ error: "Pergunta muito longa." }, 400);

    // 1) Membro ativo do workspace (com o token do usuário: pela RLS ele só enxerga a própria linha de membro).
    const { data: membro } = await userClient
      .from("workspace_membros").select("nome, status")
      .eq("workspace_id", workspace_id).eq("user_id", user.id).eq("status", "ativo").maybeSingle();
    if (!membro) return jsonResponse({ error: "Sem permissão neste workspace." }, 403);

    // 2) Liga por workspace e limite mensal (service role: nem config nem uso são editáveis por membro).
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: cfg } = await admin.from("busca_ia_config").select("ativo, limite_mensal_usd").eq("workspace_id", workspace_id).maybeSingle();
    if (!cfg || !cfg.ativo) return jsonResponse({ error: "A busca com IA não está ativada neste workspace." }, 403);

    const inicioMes = new Date(); inicioMes.setUTCDate(1); inicioMes.setUTCHours(0, 0, 0, 0);
    const { data: usos } = await admin.from("busca_ia_uso").select("custo_estimado").eq("workspace_id", workspace_id).gte("created_at", inicioMes.toISOString());
    const gastoMes = (usos ?? []).reduce((soma: number, u: any) => soma + Number(u.custo_estimado ?? 0), 0);
    if (gastoMes >= Number(cfg.limite_mensal_usd)) return jsonResponse({ error: "O limite mensal da busca com IA deste workspace foi atingido." }, 429);

    // 3) Busca no servidor, com o token de quem chamou (a RLS vale). Nada vindo do navegador entra no contexto da IA.
    const termo = (typeof termo_busca === "string" && termo_busca.trim()) ? termo_busca : pergunta;
    const { data: candidatos, error: buscaError } = await userClient.rpc("buscar_workspace", { p_workspace_id: workspace_id, p_termo: termo });
    if (buscaError) return jsonResponse({ error: `Erro na busca: ${buscaError.message}` }, 500);
    if (!candidatos || !candidatos.length) {
      return jsonResponse({ resposta: "Não encontrei isso registrado.", tokensInput: 0, tokensOutput: 0, custoEstimado: 0 });
    }

    const semMark = (s: unknown) => String(s ?? "").replace(/<\/?mark>/g, "");
    const contexto = candidatos.slice(0, MAX_CANDIDATOS).map((c: any, i: number) => {
      const quem = c.nome ? `${c.nome} | ` : "";
      if (c.origem === "atividade") {
        return `${i + 1}. ${quem}Atividade: "${c.titulo ?? ""}" | ${c.coluna === "concluida" ? "concluída" : "em aberto"} | Data: ${c.data ?? "sem data"} | Responsável: ${c.responsavel ?? "—"} | Resumo: ${semMark(c.trecho)}`;
      }
      if (c.origem === "pendencia") {
        return `${i + 1}. ${quem}Pendência (${c.coluna}): "${c.titulo ?? ""}" | Observação: ${semMark(c.trecho)}`;
      }
      return `${i + 1}. ${quem}Nota: ${semMark(c.trecho)}`;
    }).join("\n");

    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "Content-Type": "application/json" },
      body: JSON.stringify({
        model: MODELO,
        max_tokens: 400,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: `Dados encontrados:\n${contexto}\n\nPergunta: ${pergunta}` }],
      }),
    });
    if (!anthropicRes.ok) {
      const detalhe = await anthropicRes.text();
      return jsonResponse({ error: `Erro ao consultar a IA (${anthropicRes.status}): ${detalhe}` }, 502);
    }

    const anthropicJson = await anthropicRes.json();
    const resposta = (anthropicJson.content ?? []).map((b: any) => b.text ?? "").join("").trim();
    const tokensInput = anthropicJson.usage?.input_tokens ?? 0;
    const tokensOutput = anthropicJson.usage?.output_tokens ?? 0;
    const custoEstimado = (tokensInput / 1_000_000) * PRECO_INPUT_POR_MILHAO + (tokensOutput / 1_000_000) * PRECO_OUTPUT_POR_MILHAO;

    // Registrar o uso não bloqueia a resposta se falhar (a chamada já foi paga).
    await admin.from("busca_ia_uso").insert({
      workspace_id, user_id: user.id, pessoa: membro.nome, termo: pergunta,
      tokens_input: tokensInput, tokens_output: tokensOutput, custo_estimado: custoEstimado,
    });

    return jsonResponse({ resposta, tokensInput, tokensOutput, custoEstimado });
  } catch (e) {
    return jsonResponse({ error: String(e) }, 500);
  }
});
