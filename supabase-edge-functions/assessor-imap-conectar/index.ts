// Conecta uma caixa de e-mail por IMAP (Yahoo e outros sem login OAuth aberto para apps) usando uma
// "senha de app" criada pela própria pessoa no provedor. Testa o login antes de guardar; a senha vai
// direto para o Supabase Vault (assessor_email_salvar_conta_imap, só service_role) e nunca volta para a tela.
// Sempre responde 200 com { ok, erro } para a tela mostrar a mensagem certa.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clienteImap, erroDeLogin, IMAP_HOSTS } from "./imap.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const sb = createClient(SUPABASE_URL, SERVICE_KEY);
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (o: unknown) => new Response(JSON.stringify(o), { headers: { ...cors, "content-type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const authz = req.headers.get("Authorization") ?? "";
    const uc = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authz } } });
    const { data: u } = await uc.auth.getUser(authz.replace(/^Bearer\s+/i, ""));
    if (!u?.user) return json({ ok: false, erro: "Sessão expirada. Entre de novo no Taskfull." });

    const { workspace_id, provedor, email, senha } = await req.json();
    const cfg = IMAP_HOSTS[String(provedor)];
    if (!cfg) return json({ ok: false, erro: "Provedor não suportado." });
    const em = String(email ?? "").trim().toLowerCase();
    const pw = String(senha ?? "").replace(/\s+/g, "");
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(em) || pw.length < 8) return json({ ok: false, erro: "Informe o e-mail e a senha de app." });

    // Só no perfil Pessoal do próprio usuário.
    const [{ data: ws }, { data: membro }] = await Promise.all([
      sb.from("workspaces").select("perfil_tipo").eq("id", workspace_id).maybeSingle(),
      sb.from("workspace_membros").select("id").eq("workspace_id", workspace_id).eq("user_id", u.user.id).eq("status", "ativo").maybeSingle(),
    ]);
    if (ws?.perfil_tipo !== "pessoal" || !membro) return json({ ok: false, erro: "O assessor só está disponível no seu perfil Pessoal." });

    const client = clienteImap(provedor, em, pw);
    try {
      await client.connect();
      await client.logout().catch(() => {});
    } catch (e) {
      return json({
        ok: false,
        erro: erroDeLogin(e)
          ? `O ${cfg.nome} recusou o login. Confira o e-mail e use uma SENHA DE APP (não a sua senha normal).`
          : `Não consegui falar com o servidor do ${cfg.nome}: ${String((e as Error).message).slice(0, 150)}`,
      });
    }

    const { error } = await sb.rpc("assessor_email_salvar_conta_imap", {
      p_user: u.user.id, p_workspace: workspace_id, p_provedor: provedor, p_email: em, p_senha: pw,
    });
    if (error) return json({ ok: false, erro: error.message });
    return json({ ok: true, email: em });
  } catch (e) {
    return json({ ok: false, erro: `Erro inesperado: ${(e as Error).message}` });
  }
});
