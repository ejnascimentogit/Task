// Conexão do Gmail (OAuth do Google) para o Assessor Pessoal.
// GET ?iniciar=<state>        -> redireciona para a tela de consentimento do Google (com o e-mail digitado como login_hint)
// GET ?code=...&state=...      -> troca o código, guarda o refresh token no Vault e volta pro Taskfull
// Sem JWT de propósito: quem chega aqui é o navegador vindo do Google. A segurança é o
// `state` aleatório, de uso único e com validade de 10 min, gerado por assessor_email_iniciar().
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CLIENT_ID = (Deno.env.get("GOOGLE_CLIENT_ID") ?? "").trim();
const CLIENT_SECRET = (Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "").trim();
const TASKFULL_URL = "https://taskfull.ejnascimento1.workers.dev/";
const REDIRECT_URI = `${SUPABASE_URL}/functions/v1/assessor-email-callback`;
const ESCOPO = "https://www.googleapis.com/auth/gmail.readonly";

const sb = createClient(SUPABASE_URL, SERVICE_KEY);

function voltar(params: Record<string, string>) {
  const u = new URL(TASKFULL_URL);
  for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
  return Response.redirect(u.toString(), 302);
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  try {
    if (!CLIENT_ID || !CLIENT_SECRET) {
      return voltar({ email: "erro", msg: "Integração com o Google ainda não configurada no servidor." });
    }

    const iniciar = url.searchParams.get("iniciar");
    if (iniciar) {
      const { data } = await sb.from("assessor_email_estados").select("state, email_esperado")
        .eq("state", iniciar).gte("expira_em", new Date().toISOString()).maybeSingle();
      if (!data) return voltar({ email: "erro", msg: "Link de conexão expirado. Tente de novo." });
      const g = new URL("https://accounts.google.com/o/oauth2/v2/auth");
      g.searchParams.set("client_id", CLIENT_ID);
      g.searchParams.set("redirect_uri", REDIRECT_URI);
      g.searchParams.set("response_type", "code");
      g.searchParams.set("scope", ESCOPO);
      g.searchParams.set("access_type", "offline");
      g.searchParams.set("prompt", "consent");
      g.searchParams.set("state", iniciar);
      if (data.email_esperado) g.searchParams.set("login_hint", data.email_esperado);
      return Response.redirect(g.toString(), 302);
    }

    const erroGoogle = url.searchParams.get("error");
    if (erroGoogle) {
      return voltar({ email: "erro", msg: erroGoogle === "access_denied" ? "Você cancelou a autorização no Google." : `Google recusou: ${erroGoogle}` });
    }

    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    if (!code || !state) return new Response("Requisição inválida", { status: 400 });

    const tok = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code, client_id: CLIENT_ID, client_secret: CLIENT_SECRET,
        redirect_uri: REDIRECT_URI, grant_type: "authorization_code",
      }),
    }).then((r) => r.json());
    if (!tok.access_token) {
      return voltar({ email: "erro", msg: `Falha ao autorizar no Google (${tok.error ?? "sem token"}).` });
    }
    if (!String(tok.scope ?? "").includes("gmail.readonly")) {
      return voltar({ email: "erro", msg: "A permissão de leitura do Gmail não foi marcada. Conecte de novo e marque a caixa do Gmail." });
    }

    const perfil = await fetch("https://gmail.googleapis.com/gmail/v1/users/me/profile", {
      headers: { Authorization: `Bearer ${tok.access_token}` },
    }).then((r) => r.json());
    const email = String(perfil.emailAddress ?? "(desconhecido)").toLowerCase();

    const { error } = await sb.rpc("assessor_email_salvar_conta", {
      p_state: state, p_email: email, p_refresh: tok.refresh_token ?? null,
    });
    if (error) return voltar({ email: "erro", msg: error.message });

    return voltar({ email: "conectado", provedor: "gmail", conta: email });
  } catch (e) {
    return voltar({ email: "erro", msg: `Erro inesperado: ${(e as Error).message}` });
  }
});
