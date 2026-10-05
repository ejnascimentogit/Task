// Edge Function `cronograma-criar-login`: cria (ou gera nova senha provisória para) o login do CLIENTE de um projeto, no Cronograma.
// Precisa da service role (só ela cria contas), então não pode rodar no navegador. SUPABASE_URL, SUPABASE_ANON_KEY e SUPABASE_SERVICE_ROLE_KEY já vêm injetados pelo runtime.
// Segurança: valida o JWT de quem chamou e confere, COM O TOKEN DELE (RLS), que ele enxerga o projeto, que é ADMIN do workspace e que o workspace é do perfil
// Gestão de Projeto. Só depois troca pro client privilegiado. A senha provisória é aleatória (nunca uma senha fixa), aparece uma única vez e o cliente é
// obrigado a trocá-la no primeiro acesso. O e-mail é sintético (.invalid: nunca recebe mensagem de ninguém).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DOMINIO_LOGIN = "cliente.taskfull.invalid";
const ALFABETO = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
function aleatorio(n: number): string {
  const b = new Uint8Array(n);
  crypto.getRandomValues(b);
  return Array.from(b, (x) => ALFABETO[x % ALFABETO.length]).join("");
}
function slugify(str: string): string {
  return str.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Sem autenticação." }, 401);

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) return jsonResponse({ error: "Sessão inválida." }, 401);

    const { entidade_id, acao } = await req.json();
    if (!entidade_id) return jsonResponse({ error: "Informe entidade_id." }, 400);

    // Com o token de quem chamou: pela RLS, só enxerga o projeto se for membro do workspace.
    const { data: ent } = await userClient.from("entidades").select("id, nome, workspace_id").eq("id", entidade_id).maybeSingle();
    if (!ent) return jsonResponse({ error: "Projeto não encontrado." }, 404);
    const { data: souAdmin } = await userClient.rpc("is_admin", { ws_id: ent.workspace_id });
    if (!souAdmin) return jsonResponse({ error: "Só administradores do workspace podem criar o login do cliente." }, 403);
    const { data: ws } = await userClient.from("workspaces").select("perfil_tipo").eq("id", ent.workspace_id).maybeSingle();
    if (!ws || ws.perfil_tipo !== "projeto") return jsonResponse({ error: "O Cronograma só existe no perfil Gestão de Projeto." }, 403);

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: acesso } = await admin.from("cronograma_acessos").select("entidade_id, user_id, usuario").eq("entidade_id", ent.id).maybeSingle();

    if (acesso) {
      if (acao !== "resetar") return jsonResponse({ error: "Esse projeto já tem login. Use \"Gerar nova senha\"." }, 409);
      if (!acesso.user_id) return jsonResponse({ error: "A conta desse login foi removida. Fale com o suporte." }, 409);
      const senha = aleatorio(10);
      const { error: upErr } = await admin.auth.admin.updateUserById(acesso.user_id, { password: senha });
      if (upErr) return jsonResponse({ error: `Erro ao gerar a nova senha: ${upErr.message}` }, 500);
      await admin.from("cronograma_acessos").update({ senha_trocada: false }).eq("entidade_id", ent.id);
      return jsonResponse({ usuario: acesso.usuario, senha });
    }
    if (acao === "resetar") return jsonResponse({ error: "Esse projeto ainda não tem login." }, 404);

    const base = slugify(ent.nome).slice(0, 24) || "projeto";
    const usuario = `${base}-${aleatorio(4).toLowerCase()}`;
    const email = `${usuario}@${DOMINIO_LOGIN}`;
    const senha = aleatorio(10);
    const { data: novo, error: createError } = await admin.auth.admin.createUser({
      email, password: senha, email_confirm: true, user_metadata: { cliente_cronograma: true },
    });
    if (createError || !novo?.user) return jsonResponse({ error: `Erro ao criar a conta: ${createError?.message ?? "desconhecido"}` }, 500);

    const { error: insErr } = await admin.from("cronograma_acessos").insert({
      entidade_id: ent.id, workspace_id: ent.workspace_id, user_id: novo.user.id, usuario,
    });
    if (insErr) {
      await admin.auth.admin.deleteUser(novo.user.id);   // não deixa conta órfã
      return jsonResponse({ error: `Erro ao vincular o login ao projeto: ${insErr.message}` }, 500);
    }
    return jsonResponse({ usuario, senha });
  } catch (e) {
    return jsonResponse({ error: String(e) }, 500);
  }
});
