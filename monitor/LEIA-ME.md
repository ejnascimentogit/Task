# Vigia externo (plano B de avisos)

Manda mensagem para você quando **qualquer coisa** que sustenta o Taskfull ou o e-commerce parar. Roda num Cloudflare Worker (grátis, a cada 5 min), **fora do Supabase, do Docker e do seu computador**: se o Supabase cair (como em 22/10/2026, "JWT issued at future"), o aviso ainda sai.

## O que ele confere
| Verificação | Pega o quê |
|---|---|
| Site do Taskfull | Cloudflare/site fora do ar |
| Supabase (API e banco) | o erro de 22/10 (API recusando chaves), banco parado, projeto pausado |
| Automações | lembretes do assessor e WhatsApp programado parados (o vigia do banco deixou de dar sinal) |
| Supabase (login) | serviço de autenticação |
| Servidor do WhatsApp (opcional) | WuzAPI/túnel fora do ar |
| E-commerce (`EXTRA_CHECKS`) | loja, API, painel admin e o que mais você listar; serve para o que roda em Kubernetes enquanto tiver endereço público |

Avisa depois de **2 falhas seguidas** (10 min), lembra a cada 6 h e manda "✅ voltou ao normal".

## Como ligar (uns 15 minutos, você faz uma vez)
1. **Bot só para alertas:** no Telegram, fale com @BotFather → `/newbot` → guarde o token. Mande qualquer mensagem para o bot novo e abra `https://api.telegram.org/bot<TOKEN>/getUpdates` para ver o seu `chat.id`. (Não cole o token em conversa nem em arquivo.)
2. **Banco:** rode `monitor/saude_publica.sql` no SQL Editor do Supabase (cria a função de teste; não expõe dado nenhum).
3. **Worker:** numa pasta com este código: `npx wrangler kv namespace create ESTADO` (cole o id no `wrangler.toml`), depois
   `npx wrangler secret put TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` (a chave publishable/anon, a mesma do `index.html`) e `npx wrangler deploy`.
4. **E-commerce:** `npx wrangler secret put EXTRA_CHECKS` com um JSON, por exemplo:
   `[{"nome":"Loja","url":"https://SUA-LOJA.com.br/","contem":"FullCommerce"},{"nome":"API da loja","url":"https://api.SUA-LOJA.com.br/health"}]`
   (`contem` é um texto que a página tem quando está sadia; sem ele só confere o código HTTP.)
5. **Teste:** abra `https://taskfull-vigia.<sua-conta>.workers.dev/estado` (mostra o resultado sem avisar ninguém) e `/teste?chave=<últimos 8 caracteres do token>` (manda uma mensagem de prova).

## WhatsApp no seu número (opcional, segundo canal)
O Telegram é o canal principal (não depende de nada seu). Para também receber no WhatsApp **sem usar o servidor do seu PC**, dá para usar o CallMeBot (gratuito, serviço de terceiros, não oficial): você manda uma mensagem de ativação para o número dele, recebe uma chave, e põe `CALLMEBOT_PHONE` e `CALLMEBOT_KEY` como segredos. O texto do alerta passa por esse serviço (só diz qual parte caiu). A alternativa paga e oficial é a API do WhatsApp da Meta (precisa de CNPJ).

## Limites (honestidade)
- Não enxerga **dentro** do Kubernetes (pods, memória, fila): só o que responde por endereço público. Para isso, o cluster precisa do próprio alerta (Alertmanager → Telegram), que é outra etapa.
- Se o Cloudflare inteiro cair, o vigia cai junto (raro). Um segundo vigia em outro provedor é possível depois.
