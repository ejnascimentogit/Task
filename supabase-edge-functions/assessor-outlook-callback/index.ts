// Conexão do Outlook / Hotmail / Microsoft 365 (OAuth da Microsoft) para o Assessor Pessoal.
// GET ?iniciar=<state>        -> redireciona para o login da Microsoft
// GET ?code=...&state=...      -> troca o código, guarda o refresh token no Vault e volta pro Taskfull
// GET ?acao=diagnostico        -> só o FORMATO da chave (tamanho, se parece um ID), nunca o conteúdo
// Sem JWT de propósito: quem chega aqui é o navegador vindo da Microsoft. A segurança é o
// `state` aleatório, de uso único e com validade de 10 min, gerado por assessor_email_iniciar(..., 'outlook').
// App registrado no diretório pessoal do Edimilson (ejnascimentohotmail.onmicrosoft.com), contas pessoais + qualquer organização.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// O ID do aplicativo não é segredo; a chave (MS_CLIENT_SECRET) fica só nos Secrets do Supabase.
const CLIENT_ID = (Deno.env.get("MS_CLIENT_ID") ?? "bd142941-20e0-4a25-a817-6ece10196142").trim();
const CLIENT_SECRET = (Deno.env.get("MS_CLIENT_SECRET") ?? "").trim();
const TASKFULL_URL = "https://taskfull.ejnascimento1.workers.dev/";
const REDIRECT_URI = `${SUPABASE_URL}/functions/v1/assessor-outlook-callback`;
const ESCOPO = "offline_access User.Read Mail.Read";
const AUTH = "https://login.microsoftonline.com/common/oauth2/v2.0";

const sb = createClient(SUPABASE_URL, SERVICE_KEY);

function voltar(params: Record<string, string>) {
  const u = new URL(TASKFULL_URL);
  for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
  return Response.redirect(u.toString(), 302);
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  try {
    if (url.searchParams.get("acao") === "diagnostico") {
      return Response.json({
        client_id: CLIENT_ID,
        secret_presente: CLIENT_SECRET.length > 0,
        secret_tamanho: CLIENT_SECRET.length,
        secret_parece_id_guid: /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(CLIENT_SECRET),
        secret_tem_til: CLIENT_SECRET.includes("~"),
      });
    }
    if (!CLIENT_SECRET) {
      return voltar({ email: "erro", msg: "Integração com o Outlook ainda não configurada no servidor." });
    }

    const iniciar = url.searchParams.get("iniciar");
    if (iniciar) {
      const { data } = await sb.from("assessor_email_estados").select("state")
        .eq("state", iniciar).eq("provedor", "outlook").gte("expira_em", new Date().toISOString()).maybeSingle();
      if (!data) return voltar({ email: "erro", msg: "Link de conexão expirado. Tente de novo." });
      const m = new URL(`${AUTH}/authorize`);
      m.searchParams.set("client_id", CLIENT_ID);
      m.searchParams.set("response_type", "code");
      m.searchParams.set("redirect_uri", REDIRECT_URI);
      m.searchParams.set("response_mode", "query");
      m.searchParams.set("scope", ESCOPO);
      m.searchParams.set("state", iniciar);
      m.searchParams.set("prompt", "select_account");
      return Response.redirect(m.toString(), 302);
    }

    const erro = url.searchParams.get("error");
    if (erro) {
      const desc = url.searchParams.get("error_description") ?? "";
      return voltar({ email: "erro", msg: erro === "access_denied" ? "Você cancelou a autorização na Microsoft." : `Microsoft recusou: ${erro} ${desc.slice(0, 200)}` });
    }

    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    if (!code || !state) return new Response("Requisição inválida", { status: 400 });

    const tok = await fetch(`${AUTH}/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: CLIENT_ID, client_secret: CLIENT_SECRET, code,
        redirect_uri: REDIRECT_URI, grant_type: "authorization_code", scope: ESCOPO,
      }),
    }).then((r) => r.json());
    if (!tok.access_token) {
      // A descrição da Microsoft traz o código AADSTS (ex.: chave inválida ou vencida); nunca contém a chave.
      const desc = String(tok.error_description ?? "").split("\r\n")[0].slice(0, 220);
      console.error("outlook token:", tok.error, desc);
      return voltar({ email: "erro", msg: `Falha ao autorizar na Microsoft (${tok.error ?? "sem token"}). ${desc}` });
    }
    if (!/mail\.read/i.test(String(tok.scope ?? ""))) {
      return voltar({ email: "erro", msg: "A permissão de leitura de e-mail não foi concedida. Conecte de novo e aceite." });
    }

    const eu = await fetch("https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName", {
      headers: { Authorization: `Bearer ${tok.access_token}` },
    }).then((r) => r.json());
    const email = (eu.mail || eu.userPrincipalName || "(desconhecido)").toLowerCase();

    const { error } = await sb.rpc("assessor_email_salvar_conta", {
      p_state: state, p_email: email, p_refresh: tok.refresh_token ?? null,
    });
    if (error) return voltar({ email: "erro", msg: error.message });

    return voltar({ email: "conectado", provedor: "outlook" });
  } catch (e) {
    return voltar({ email: "erro", msg: `Erro inesperado: ${(e as Error).message}` });
  }
});
