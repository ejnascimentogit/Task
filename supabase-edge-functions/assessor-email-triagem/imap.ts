// Leitura de e-mail por IMAP (Yahoo e outros provedores sem API de e-mail aberta para apps).
// Login com "senha de app" (criada pela pessoa no provedor), guardada no Supabase Vault.
// Cópia idêntica em assessor-imap-conectar/ e assessor-email-triagem/ (cada Edge Function é publicada com os próprios arquivos).
import { ImapFlow } from "npm:imapflow@1.0.164";
import { simpleParser } from "npm:mailparser@3.7.1";

export const IMAP_HOSTS: Record<string, { host: string; nome: string; link: string }> = {
  yahoo: { host: "imap.mail.yahoo.com", nome: "Yahoo", link: "https://mail.yahoo.com/" },
};

export type MsgImap = { id: string; nome: string; email: string; assunto: string; recebido: string; dataTexto: string; texto: string; link: string };

export function clienteImap(provedor: string, email: string, senha: string) {
  const cfg = IMAP_HOSTS[provedor];
  if (!cfg) throw new Error(`Provedor IMAP desconhecido: ${provedor}`);
  return new ImapFlow({ host: cfg.host, port: 993, secure: true, auth: { user: email, pass: senha }, logger: false });
}

export function erroDeLogin(e: unknown) {
  const err = e as { authenticationFailed?: boolean; responseText?: string; message?: string };
  return !!err?.authenticationFailed || /AUTHENTICATIONFAILED|invalid credentials|LOGIN failed|Command failed/i.test(`${err?.responseText ?? ""} ${err?.message ?? ""}`);
}

// Lê só a Caixa de Entrada, desde `desde`. `permitido` aplica a lista de remetentes liberados ANTES de baixar o corpo;
// `jaVistos` tira os que já foram triados. Devolve no máximo `max` mensagens (mais recentes primeiro).
export async function listarImap(
  provedor: string, email: string, senha: string, desde: Date,
  permitido: (email: string) => boolean, jaVistos: (ids: string[]) => Promise<string[]>, max: number,
): Promise<MsgImap[]> {
  const client = clienteImap(provedor, email, senha);
  await client.connect();
  const msgs: MsgImap[] = [];
  try {
    const lock = await client.getMailboxLock("INBOX");
    try {
      // deno-lint-ignore no-explicit-any
      const validade = String((client.mailbox as any)?.uidValidity ?? "0");
      const uids = ((await client.search({ since: desde }, { uid: true })) || []) as number[];
      const recentes = uids.slice(-200);
      const candidatos: (Omit<MsgImap, "texto" | "link"> & { uid: number })[] = [];
      if (recentes.length) {
        for await (const m of client.fetch(recentes, { uid: true, envelope: true, internalDate: true }, { uid: true })) {
          const de = m.envelope?.from?.[0];
          const addr = String(de?.address ?? "").toLowerCase();
          const quando = m.internalDate ? new Date(m.internalDate) : null;
          if (!permitido(addr)) continue;
          if (quando && quando < desde) continue;
          candidatos.push({
            id: `${validade}:${m.uid}`, uid: m.uid, nome: de?.name ?? "", email: addr,
            assunto: m.envelope?.subject ?? "", recebido: (quando ?? new Date()).toISOString(),
            dataTexto: m.envelope?.date ? new Date(m.envelope.date).toISOString() : "",
          });
        }
      }
      candidatos.sort((a, b) => b.recebido.localeCompare(a.recebido));
      const novos = new Set(await jaVistos(candidatos.map((c) => c.id)));
      for (const c of candidatos.filter((c) => novos.has(c.id)).slice(0, max)) {
        const m = await client.fetchOne(String(c.uid), { source: { start: 0, maxLength: 300000 } }, { uid: true });
        let texto = "";
        if (m && m.source) {
          const p = await simpleParser(m.source);
          texto = p.text || (typeof p.html === "string" ? p.html : "") || "";
        }
        msgs.push({ id: c.id, nome: c.nome, email: c.email, assunto: c.assunto, recebido: c.recebido, dataTexto: c.dataTexto, texto, link: IMAP_HOSTS[provedor].link });
      }
    } finally {
      lock.release();
    }
  } finally {
    await client.logout().catch(() => {});
  }
  return msgs;
}
