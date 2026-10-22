# Vigia externo (plano B de avisos)

Manda **WhatsApp no seu número** quando algo que sustenta o Taskfull (e depois o e-commerce) parar. Roda num Cloudflare Worker (grátis, a cada 5 min), **fora do Supabase, do Docker e do seu computador**: se o Supabase cair (como em 22/10/2026, "JWT issued at future"), o aviso ainda sai.

## O que ele confere (etapa 1: Taskfull)
| Verificação | Pega o quê |
|---|---|
| Site do Taskfull | site/Cloudflare fora do ar |
| Supabase (API e banco) | o erro de 22/10 (API recusando chaves), banco parado, projeto pausado |
| Automações | lembretes e WhatsApp programado parados (o vigia do banco deixou de dar sinal por 20 min) |
| Supabase (login) | serviço de autenticação |
| Servidor do WhatsApp (opcional, `WUZAPI_URL`) | WuzAPI/túnel fora do ar |

Avisa depois de **2 falhas seguidas** (10 min), lembra a cada 6 h e manda "✅ voltou ao normal". **Etapa 2 (e-commerce):** é só acrescentar o segredo `EXTRA_CHECKS` (exemplo no fim), sem mudar o código.

## Passo 1: ativar o WhatsApp de alerta (CallMeBot, gratuito, 2 minutos)
Serviço de terceiros e não oficial: ele envia uma mensagem de um número dele para o seu. O texto do alerta passa por ele (só diz qual parte caiu).
1. Abra https://www.callmebot.com/blog/free-api-whatsapp-messages/ e veja o número de WhatsApp que a página manda salvar nos contatos e a frase de ativação (no momento da escrita: "I allow callmebot to send me messages").
2. Do **seu** WhatsApp, envie essa frase para o número. Em instantes ele responde com a sua **apikey** (um número).
3. Guarde a apikey (não cole em conversa pública). Seu telefone entra no formato internacional, ex.: `+5581984453645`.

## Passo 2: o banco (já feito)
A função `saude_publica()` já foi criada no Supabase em 22/10 (só devolve "o banco responde" e quando o vigia interno deu o último sinal; nenhum dado de pessoa).

## Passo 3: criar o Worker pelo painel da Cloudflare (sem instalar nada, ~10 min)
1. Cloudflare → **Workers & Pages** → **Create** → **Create Worker** → nome `taskfull-vigia` → **Deploy** → **Edit code**.
2. Apague o código de exemplo e cole todo o conteúdo de `monitor/worker.js` (no GitHub: `ejnascimentogit/Task` → pasta `monitor`). **Deploy**.
3. **Storage & Databases → KV → Create** um namespace chamado `ESTADO`. Volte ao Worker → **Settings → Bindings → Add → KV namespace** → nome da variável `ESTADO`, escolha o namespace criado.
4. **Settings → Variables and Secrets → Add** (tipo **Secret**), um por vez:
   - `SUPABASE_URL` = `https://dubbmmjtbunzmdmfbbja.supabase.co`
   - `SUPABASE_ANON_KEY` = a chave publishable/anon (a mesma que está no topo do `index.html`; é pública)
   - `CALLMEBOT_PHONE` = seu telefone, ex.: `+5581984453645`
   - `CALLMEBOT_KEY` = a apikey do passo 1
   - `TESTE_CHAVE` = uma senha qualquer, curta
   - (opcional) `WUZAPI_URL` = `https://dkp-ti-004.tail8fb8f9.ts.net`
5. **Settings → Triggers → Cron Triggers → Add** → `*/5 * * * *`.

## Passo 4: testar
- Abra `https://taskfull-vigia.<sua-conta>.workers.dev/estado`: mostra cada verificação (ok ou não) **sem avisar ninguém**.
- Abra `.../teste?chave=<TESTE_CHAVE>`: manda um WhatsApp de prova para você.
- Para ver um alerta de verdade: coloque temporariamente uma `SUPABASE_ANON_KEY` errada, espere 10 min, e depois corrija e veja o "✅ voltou".

## Etapa 2: e-commerce (depois)
Segredo `EXTRA_CHECKS` com um JSON, por exemplo:
`[{"nome":"Loja","url":"https://SUA-LOJA.com.br/","contem":"FullCommerce"},{"nome":"API da loja","url":"https://api.SUA-LOJA.com.br/health"}]`
(`contem` é um texto que a página tem quando está sadia; sem ele só confere o código HTTP.)

## Limites (honestidade)
- O CallMeBot é gratuito e não oficial: costuma funcionar bem para avisos pessoais, mas não tem garantia. Por isso o código também aceita Telegram como segundo canal (`TELEGRAM_BOT_TOKEN` e `TELEGRAM_CHAT_ID`), se você quiser redundância.
- Não enxerga **dentro** do Kubernetes (pods, memória, fila): só o que responde por endereço público. Para isso, o cluster precisa do próprio alerta.
- Se o Cloudflare inteiro cair, o vigia cai junto (raro).
