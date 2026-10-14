# Servidor do WuzAPI (WhatsApp) — passo a passo

O Taskfull já está pronto para falar com o WuzAPI. Falta **uma máquina sempre ligada** rodando o WuzAPI, e dois segredos no Supabase. O WuzAPI é um programa em Go que mantém a sessão do WhatsApp de cada pessoa aberta; por isso **não roda** no Cloudflare Workers nem no Supabase.

> **Aviso importante.** O WuzAPI usa o protocolo do WhatsApp Web de forma **não oficial**. Isso viola os termos do WhatsApp: o número pode ser restringido ou bloqueado, principalmente se enviar muito ou para quem não espera. O Taskfull tem proteções (limite diário de 50 por pessoa, intervalo de 4 a 9 s entre envios, checagem se o número tem WhatsApp, aviso de consentimento), mas elas **diminuem** o risco, não o eliminam. Para clientes pagantes e escala, o caminho seguro é a API oficial da Meta (precisa de CNPJ). Usar com números de teste primeiro.

## 1. Máquina

- Uma VPS pequena basta (1 vCPU, 1 GB de RAM, Linux), por exemplo Hetzner, Contabo, DigitalOcean ou Oracle Cloud (camada gratuita). Custo típico: US$ 4 a 6 por mês.
- Docker e Docker Compose instalados.
- Não é necessário abrir portas se usar o Cloudflare Tunnel (passo 3).

## 2. Subir o WuzAPI (Docker)

Repositório oficial: https://github.com/asternic/wuzapi (há `docker-compose.yml` e `.env.sample`). Resumo:

```bash
git clone https://github.com/asternic/wuzapi.git && cd wuzapi
cp .env.sample .env
```

No `.env`, defina **antes de subir** (gere valores longos e aleatórios, ex.: `openssl rand -hex 32`):

```
WUZAPI_ADMIN_TOKEN=<token de admin longo e secreto>
WUZAPI_GLOBAL_ENCRYPTION_KEY=<32+ caracteres aleatórios>
WUZAPI_GLOBAL_HMAC_KEY=<32+ caracteres aleatórios>
TZ=America/Sao_Paulo
```

```bash
docker compose up -d
```

- Guarde o `WUZAPI_ADMIN_TOKEN`: sem ele não há acesso de administrador. **Nunca** coloque em arquivo do repositório nem em conversa.
- Faça backup do volume de dados do WuzAPI (guarda as sessões; se perder, todo mundo precisa ler o QR de novo).

## 3. Endereço público com HTTPS (Cloudflare Tunnel, grátis)

O Supabase precisa alcançar o WuzAPI por HTTPS. Com `cloudflared` (já usamos Cloudflare no Taskfull):

1. Zero Trust → Networks → Tunnels → criar túnel e instalar o `cloudflared` na VPS.
2. Apontar um hostname (ex.: `wuzapi.seudominio.com`) para `http://localhost:8080`.
3. Não expor a porta 8080 diretamente na internet.

(Alternativa: Caddy ou Nginx com certificado Let's Encrypt, exige domínio e portas 80/443.)

## 4. Segredos no Supabase

Supabase → Edge Functions → Secrets (projeto `painel-workspaces`):

| Segredo | Valor |
|---|---|
| `WUZAPI_URL` | `https://wuzapi.seudominio.com` (sem barra no fim) |
| `WUZAPI_ADMIN_TOKEN` | o mesmo do `.env` do WuzAPI |

Pronto: a aba WhatsApp deixa de mostrar "servidor não configurado".

## 5. Teste de fumaça (com o seu número)

1. No Taskfull, aba **Usuários** → ⚙️ Gerenciar na sua conta (o master já tem tudo) e a aba **WhatsApp** aparece.
2. Marque o aviso e clique em **Conectar WhatsApp**. Leia o QR em *WhatsApp → Aparelhos conectados → Conectar um aparelho*.
3. Envie uma mensagem **para você mesmo** (agora) e uma **programada para daqui a 2 minutos**. Confira que chegam e que a lista mostra "Enviada".
4. Teste um número sem WhatsApp (deve dar "Este número não tem WhatsApp") e o botão Desconectar.

## 6. O que conferir no primeiro teste real (a documentação do WuzAPI é inconsistente)

- **Cabeçalho do token de usuário:** o código manda `token: <token>` e, para admin, `Authorization: <admin>`. Se a tela mostrar erro 401 ao conectar, trocar em `envio.ts` (função `chamar`) para `Authorization` no token de usuário. Ao mudar, copiar o arquivo para as duas funções (`whatsapp-api` e `whatsapp-agendadas`) e publicar as duas.
- **`/session/status`:** o código espera `data.LoggedIn` e `data.Connected`; o número conectado é lido de `data.jid` (se vier com outro nome, o telefone aparece vazio, mas envia normalmente).
- **`/user/check`:** usado antes de cada envio; o JID devolvido corrige o nono dígito dos celulares.
- Versões novas do WuzAPI podem mudar campos: conferir o Swagger do próprio servidor em `/api`.

## 7. Manutenção

- Atualizar o WuzAPI de tempos em tempos (`docker compose pull && docker compose up -d`): o WhatsApp muda e versões antigas deixam de conectar.
- Se uma pessoa não consegue mais enviar e a tela diz "foi desconectado", é só conectar de novo (novo QR).
- Limite diário por pessoa: coluna `whatsapp_contas.limite_diario` (padrão 50), alterada pelo SQL Editor.

## 8. Vigia e alertas (o Taskfull avisa quando algo cai)

O Taskfull tem um vigia que roda **a cada 10 minutos** (cron `whatsapp-vigia`, na função `whatsapp-agendadas` com corpo `{"tarefa":"vigia"}`):

- "Toca" o servidor do WuzAPI. Isso também **impede hospedagem grátis de dormir** por falta de acesso. Não manda mensagem de WhatsApp nenhuma.
- Confere se cada sessão marcada como conectada continua logada.
- Só alerta depois de **2 falhas seguidas** (20 min), lembra a cada 6 h enquanto o problema durar e avisa quando volta.
- **Onde aparece o alerta:** (1) faixa vermelha/amarela no topo do Taskfull, para o master (servidor e sessões de todos) e para a própria pessoa (a sessão dela); (2) caixa "Saúde do serviço" com os últimos eventos, na aba WhatsApp, só para o master; (3) mensagem no Telegram do master (uma só, mesmo que várias sessões caiam juntas) e no Telegram de cada pessoa afetada, se ela tiver conectado; (4) registro em `whatsapp_saude_estado` e `whatsapp_saude_eventos` (eventos com mais de 90 dias são apagados).
- **Reinício do servidor:** se a hospedagem reiniciar e o WuzAPI perder as sessões, todas caem juntas. O vigia marca cada conta como desconectada com a explicação, avisa cada pessoa para ler o QR de novo, e as **mensagens programadas esperam** (até 3 tentativas de 30 em 30 min) em vez de virar erro.

## 9. Limpeza: no servidor, nunca nas mensagens do Supabase

Decisão do Edimilson (2026-10-14): **o Taskfull não apaga mensagens do Supabase** (`whatsapp_mensagens` guarda tudo, para não se perder nada importante das pessoas). Cada mensagem ocupa menos de 2 KB. Se o espaço do Supabase um dia apertar, decidir com ele antes de apagar qualquer coisa.

A limpeza vale para o **servidor de hospedagem** (o WuzAPI):
- Não ativar sincronização de histórico (`days_to_sync_history` = 0, o padrão) e assinar só os eventos necessários (o Taskfull usa só `ReadReceipt`). Assim o WuzAPI quase não acumula mensagens.
- Limitar o tamanho dos logs do Docker (no `docker-compose.yml`, `logging: driver: json-file`, `max-size: 10m`, `max-file: "3"`).
- Limpeza semanal do Docker (`docker system prune -f`, em um agendador do próprio servidor) para não acumular imagens antigas.
- Acompanhar o espaço em disco da máquina de vez em quando. Ainda **não sabemos o que mais acumula** no WuzAPI real (tabelas internas da biblioteca do WhatsApp): conferir depois do primeiro mês de uso.
