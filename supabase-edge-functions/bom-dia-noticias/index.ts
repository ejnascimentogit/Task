// bom-dia-noticias — manchetes para o bloco "Bom dia" do Resumo do Dia (perfil Pessoal).
// Sem IA e sem chave: lê o RSS aberto do Google Notícias (mundo, país, estado e cidade) e devolve
// só título, fonte, data e link (o texto das matérias nunca é copiado).
// Publicar com verify_jwt = true. Entrada (POST, JSON): { cidade: "Campinas", estado: "São Paulo", pais: "Brasil" }.
// Fora do Brasil, o bloco "país" vem de uma busca pelo nome do país.
// Saída: { mundo: [...], pais: [...], estado: [...], cidade: [...] } com { titulo, fonte, link, data }.

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};
const BASE = "https://news.google.com/rss";
const SUFIXO = "hl=pt-BR&gl=BR&ceid=BR:pt-419";
const POR_BLOCO = 5;

function decodificar(s: string): string {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&")
    .replace(/<[^>]+>/g, "").trim();
}
function tag(bloco: string, nome: string): string {
  const m = bloco.match(new RegExp(`<${nome}[^>]*>([\\s\\S]*?)</${nome}>`));
  return m ? decodificar(m[1]) : "";
}

async function manchetes(url: string): Promise<{ titulo: string; fonte: string; link: string; data: string }[]> {
  try {
    const r = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0 (Taskfull bom-dia)" }, signal: AbortSignal.timeout(8000) });
    if (!r.ok) return [];
    const xml = await r.text();
    const itens = xml.split("<item>").slice(1);
    const saida = [];
    for (const it of itens) {
      let titulo = tag(it, "title");
      const fonte = tag(it, "source");
      if (fonte && titulo.endsWith(" - " + fonte)) titulo = titulo.slice(0, -(fonte.length + 3));
      const link = tag(it, "link");
      if (!titulo || !/^https?:\/\//.test(link)) continue;
      saida.push({ titulo, fonte, link, data: tag(it, "pubDate") });
      if (saida.length >= POR_BLOCO) break;
    }
    return saida;
  } catch (_) {
    return [];
  }
}
const busca = (q: string) => `${BASE}/search?q=${encodeURIComponent(q + " when:2d")}&${SUFIXO}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  let corpo: { cidade?: string; estado?: string; pais?: string } = {};
  try { corpo = await req.json(); } catch (_) { /* sem corpo: só mundo e país */ }
  const cidade = String(corpo.cidade || "").slice(0, 80).trim();
  const paisNome = String(corpo.pais || "Brasil").slice(0, 80).trim();
  const estado = String(corpo.estado || "").slice(0, 80).trim();
  const [mundo, paisLista, est, cid] = await Promise.all([
    manchetes(`${BASE}/headlines/section/topic/WORLD?${SUFIXO}`),
    paisNome === "Brasil" ? manchetes(`${BASE}/headlines/section/topic/NATION?${SUFIXO}`) : manchetes(busca(paisNome)),
    estado ? manchetes(busca(estado + (paisNome !== "Brasil" ? " " + paisNome : ""))) : Promise.resolve([]),
    cidade ? manchetes(busca(cidade + (estado ? " " + estado : "") + (paisNome !== "Brasil" ? " " + paisNome : ""))) : Promise.resolve([]),
  ]);
  return new Response(JSON.stringify({ mundo, pais: paisLista, estado: est, cidade: cid }), { headers: CORS });
});
